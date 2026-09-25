# bankinventory.gd — controls the bank UI screen.
# attached to the root of bankinventory.tscn at res://scene/ui/bank/
#
# architecture:
# the bank is ACCOUNT-SHARED storage — items here are safe from death loss
# and accessible by ALL characters on this save file. uses the same
# InventoryContainer / InventorySlot system as the carry inventory, so
# drag/drop between carry and bank just works.
#
# data flow:
# - on open: pull fresh bank state from CharacterData (in case another
#   character modified it during a previous session)
# - on drag/drop: atomically save to disk via CharacterData.set_bank_inventory
# - on close: final save + hide panel + emit closed signal
#
# gold transfers:
# typed amount + deposit/withdraw buttons. transfers carry gold (per-character)
# <-> bank_gold (account-shared) via CharacterData.deposit_gold_to_bank() and
# withdraw_gold_from_bank(). both methods are atomic — player gold AND bank
# gold update in a single save_data() call.
extends Control
class_name BankInventory


# =============================================================================
# SIGNALS
# =============================================================================

# emitted when the bank closes — close button OR walk-away from chest.
#
# NOTE: nothing is connected to this right now. the comment here used to claim
# the HUD listens for cleanup hooks; it doesn't, and the inventory-hiding that
# close_bank() does below is the cleanup that claim was describing. left in
# place as a hook for anything that later needs to react to the bank closing.
signal closed


# =============================================================================
# STATE
# =============================================================================

# the player whose carry gold/inventory we're swapping items with.
# resolved lazily from the "player" group on first access.
var player: Node = null


# =============================================================================
# NODE REFERENCES
# =============================================================================

# the bank slot grid — uses InventoryContainer so drag/drop works seamlessly
# with the carry inventory's slots.
@onready var bank_container: InventoryContainer = %bankcontainer

# gold UI controls — paths match the bankinventory.tscn scene structure
@onready var gold_label:   Label    = $mainpanel/margincontainer/vboxcontainer/currencypanel/currencyvbox/goldcontainer/goldlabel
@onready var gold_input:   LineEdit = $mainpanel/margincontainer/vboxcontainer/currencypanel/currencyvbox/goldinput
@onready var deposit_btn:  Button   = $mainpanel/margincontainer/vboxcontainer/goldbuttons/depositbuttons
@onready var withdraw_btn: Button   = $mainpanel/margincontainer/vboxcontainer/goldbuttons/withdrawbutton

# close button at the top-right of the panel
@onready var close_button: Button = $mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/closebutton


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_wire_buttons()
	_wire_gold_input()
	_wire_bank_container()
	visible = false


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _wire_buttons() -> void:
	# connect close + deposit + withdraw buttons to their handlers.
	# each is null-guarded so missing scene nodes don't crash _ready.
	if close_button != null:
		close_button.pressed.connect(close_bank)
	if deposit_btn != null:
		deposit_btn.pressed.connect(_on_deposit_pressed)
	if withdraw_btn != null:
		withdraw_btn.pressed.connect(_on_withdraw_pressed)


func _wire_gold_input() -> void:
	# gold input field gets two callbacks:
	# - text_changed: strips non-digit chars as the player types
	# - text_submitted: pressing enter runs the transfer (see that handler)
	if gold_input == null:
		return
	gold_input.text_changed.connect(_on_gold_input_changed)
	gold_input.text_submitted.connect(_on_gold_input_submitted)


func _wire_bank_container() -> void:
	# listen for bank inventory changes (drag/drop swaps) so we can
	# atomically persist on every change.
	if bank_container == null:
		push_warning("BankInventory: bankcontainer node not found")
		return
	if not bank_container.inventory_changed.is_connected(_on_bank_changed):
		bank_container.inventory_changed.connect(_on_bank_changed)

	# Marks every slot in this grid as a bank slot, which is what
	# InventorySlot._drop_data() branches on to tell a rearrange from a
	# transfer. Set here rather than in the scene because the container
	# instantiates its own slots.s
	if bank_container.has_method("set_slot_type"):
		bank_container.set_slot_type(InventorySlot.BANK_SLOT_TYPE)

	if not bank_container.transfer_requested.is_connected(_on_transfer_requested):
		bank_container.transfer_requested.connect(_on_transfer_requested)
	if not bank_container.slot_double_clicked.is_connected(_on_bank_slot_double_clicked):
		bank_container.slot_double_clicked.connect(_on_bank_slot_double_clicked)


func _wire_carry_container(connected: bool) -> void:
	# THE BACKPACK HALF, CONNECTED ONLY WHILE THE BANK IS OPEN.
	#
	# A transfer can be aimed either way, and the container that relays the
	# request is whichever one the drag LANDED on - so dragging out of the bank
	# is announced by the backpack, not by us. Double-click is the same story in
	# reverse: double-clicking a backpack slot has to mean "deposit" here and
	# must go back to meaning nothing the moment the chest closes, or the first
	# potion anyone double-clicks in the field disappears into the bank.
	var carry: Node = _get_player_inventory_container()
	if carry == null:
		return
	if not carry.has_signal("transfer_requested") or not carry.has_signal("slot_double_clicked"):
		push_warning("BankInventory: carry grid has no transfer signals — drag and double-click will not reach the server")
		return

	if connected:
		if not carry.transfer_requested.is_connected(_on_transfer_requested):
			carry.transfer_requested.connect(_on_transfer_requested)
		if not carry.slot_double_clicked.is_connected(_on_carry_slot_double_clicked):
			carry.slot_double_clicked.connect(_on_carry_slot_double_clicked)
		return

	if carry.transfer_requested.is_connected(_on_transfer_requested):
		carry.transfer_requested.disconnect(_on_transfer_requested)
	if carry.slot_double_clicked.is_connected(_on_carry_slot_double_clicked):
		carry.slot_double_clicked.disconnect(_on_carry_slot_double_clicked)


# =============================================================================
# PUBLIC API — OPEN / CLOSE
# =============================================================================

func open_bank() -> void:
	# THIS USED TO CALL CharacterData.load_data() AND THAT WAS DESTRUCTIVE.
	#
	# The reasoning was "reload from disk in case another character updated
	# the bank between opens." It doesn't hold: the bank lives in
	# account_data, account_data is account-shared and held in memory by one
	# autoload for the whole session, and nothing else writes that file while
	# the game is running. The in-memory copy IS the current one. Swapping
	# characters never made it stale, because both characters were reading the
	# same object.
	#
	# What the reload actually did was replace live state with whatever was
	# last flushed. load_data() overwrites character_slots AND
	# active_character_index wholesale, and save_data() is debounced by
	# SAVE_DEBOUNCE_SECONDS — so opening a chest inside that window threw away
	# every unsaved thing the character had just done. Worse, _save_pending
	# stayed true, so the debounce then wrote the stale reloaded values back
	# out as if they were new. Kill a monster, walk to the bank, open it, and
	# the XP was gone from memory and then gone from disk, silently.
	#
	# active_character_index snapping back to the on-disk value is the other
	# half: every save_character_state() after that writes the live character
	# into whichever slot the file named, which can be a DIFFERENT character.
	#
	# There is nothing to reload. Just open.
	_load_bank_contents()
	_update_gold_ui()
	_center_window()

	visible = true

	# force inventory open so player can drag items between bank and carry
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_inventory"):
		hud.show_inventory()

	# AFTER show_inventory(), not before - the container has to exist before it
	# can be connected to.
	_wire_carry_container(true)


func close_bank() -> void:
	# BEFORE ANYTHING ELSE. hide_inventory() below may free the backpack
	# container, and a connection left on a freed node is the "double-clicking a
	# potion deposited it into a bank I closed ten minutes ago" bug.
	_wire_carry_container(false)

	# persist bank state before hiding (crash-safe — even if the player
	# alt-F4s right after this, the bank is already on disk).
	_save_bank_contents()
	visible = false

	# open_bank() force-opens the carry inventory so items can be dragged
	# between the two panels. that pairing has to be symmetrical: the bank
	# opened it, so the bank puts it away. without this, walking away from the
	# chest left the inventory sitting open on its own, with the thing it was
	# opened to drag to already gone.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("hide_inventory"):
		hud.hide_inventory()

	# make the "already on disk" promise above actually true. set_bank_inventory()
	# routes through save_data(), which is DEBOUNCED — so until this flush, the
	# comment was describing a write that hadn't happened yet and a crash inside
	# the debounce window would have taken the deposit with it. closing a bank is
	# rare enough that an immediate write costs nothing, and it is exactly the
	# moment a player believes their items are safe.
	CharacterData.flush_save()

	closed.emit()


func _center_window() -> void:
	# place the panel centered on the viewport.
	# called every open so a different screen resolution stays centered.
	var screen_size: Vector2 = get_viewport_rect().size
	global_position = (screen_size / 2) - (size / 2)


# =============================================================================
# BANK INVENTORY PERSISTENCE
# =============================================================================

func _load_bank_contents() -> void:
	# pull bank data from CharacterData and populate the grid.
	# always reads fresh so changes from other characters are picked up.
	if bank_container == null:
		return
	var saved: Array = CharacterData.get_bank_inventory()
	bank_container.load_save_array(saved)


func _save_bank_contents() -> void:
	# serialize current bank contents and persist via CharacterData.
	# CharacterData.set_bank_inventory() writes to disk internally,
	# so this is atomic from the caller's perspective.
	if bank_container == null:
		return
	var saved: Array = bank_container.to_save_array()
	CharacterData.set_bank_inventory(saved)


func _on_bank_changed() -> void:
	# fired on every drag/drop into or out of a bank slot.
	# saves immediately so a crash can never lose more than the last swap.
	#
	# THIS ALSO FIRES WHEN _apply_grids() PAINTS THE SERVER'S ARRAY, AND IT MUST.
	#
	# It looks wrong in the Flask log - a POST /api/bank/items answered by a PUT
	# /api/account/bank a moment later, the client asserting a whole array right
	# after asking the server to author one. It was briefly suppressed for that
	# reason and that was a data-loss bug:
	#
	#   set_bank_inventory() is what updates CharacterData's IN-MEMORY bank, and
	#   save_data() is debounced. Skip it here and the grid holds the server's
	#   post-transfer array while CharacterData still holds the PRE-transfer one
	#   - then the next flush, from anywhere, writes that stale array over the
	#   server's bank_items and the deposit is gone from both sides.
	#
	# The echo is harmless because the array being written is the server's own.
	# lootbaginventory.gd:376 saves after a grant for exactly this reason. What
	# actually removes these writes is making PUT /api/account/bank refuse
	# anything that is not a permutation of what it already holds, so a client
	# cannot assert contents at all - see docs/inventoryauthority.md. Until
	# then, keeping memory and server in step beats a tidier log.
	_save_bank_contents()


# =============================================================================
# ITEM TRANSFERS — THE SERVER OWNS BOTH GRIDS
# =============================================================================
#
# Gold already worked this way: /api/bank/gold is an op, because the server
# holds both balances and can conserve the total. Items now do too.
#
# What this replaces: a drag moved the stack between the two containers
# locally, then each container saved its own whole array. Nothing tied those
# two writes together, so the server saw one array claiming 5 potions fewer and
# another claiming 5 more, with no way to tell that pair from a pair that did
# not add up. Whole-array writes cannot conserve anything.
#
# Rearranging INSIDE one grid still saves the whole array, and that is fine for
# now because no items cross a boundary - but it is the last place the client
# still asserts a container's contents. Closing it means validating the PUT as
# a permutation of what is stored. See docs/inventoryauthority.md.

const TRANSFER_TIMEOUT := 4.0

var _transferring: bool = false


func request_transfer(op: String, item_id: String, quantity: int) -> void:
	if item_id == "" or quantity <= 0:
		return

	if _transferring:
		# Silent. The player acted twice inside the time one request takes,
		# which is not a mistake worth a message - and the request already out
		# is about to redraw both grids underneath them anyway.
		return

	if not Api.is_logged_in():
		# NO LOCAL FALLBACK. Moving the item because the server could not be
		# asked is the whole exploit: a client that can move items by making a
		# request fail does not need permission for anything.
		_notify("Not connected — can't move that.")
		return

	# Captured before the await. Four seconds is long enough to close the panel,
	# swap characters or die, and the item has already moved on the server by
	# the time the response lands.
	var character_slot: int = CharacterData.active_character_index

	# NOT named `player` - that is a member on this panel, and shadowing it here
	# would mean the post-await notify could quietly read the live one instead
	# of the captured one, which is the whole point of capturing it.
	var acting_player: Node = _get_player()
	if not is_instance_valid(acting_player):
		acting_player = null

	_transferring = true
	var res: Dictionary = await Api.post("/api/bank/items", {
		"slot": character_slot,
		"op": op,
		"item_id": item_id,
		"quantity": quantity,
	}, TRANSFER_TIMEOUT)

	# PAST A FOUR-SECOND AWAIT. Everything this function needs was captured
	# before it — character_slot, acting_player — but nothing checked that THIS
	# PANEL still exists. Logout frees it (characterhud.gd queue_frees every
	# panel) and a ladder or teleporter changes the scene out from under it,
	# and the server has already moved the item by then. Same guard, same
	# reason, as cookingscreen.gd two files over.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	_transferring = false

	if not res.get("ok", false):
		_handle_transfer_refusal(res, acting_player)
		return

	_apply_grids(res.get("data", {}))
	_update_gold_ui()


func _apply_grids(data: Dictionary) -> void:
	# BOTH SIDES FROM ONE RESPONSE.
	#
	# The server decided which cell the stack landed in, on both grids, using
	# the same placement rule it uses for loot. Applying its arrays rather than
	# moving the stack where the player dropped it is what stops the client and
	# the server laying the same transfer out differently - and a disagreement
	# about layout becomes a disagreement about contents the next time the
	# client saves.
	#
	# load_server_array() ignores an empty array rather than emptying the grid,
	# because a missing key and an empty bag are not the same thing.
	#
	# Each load fires inventory_changed, and the savers listening to it are
	# SUPPOSED to run - that is what carries the server's array into
	# CharacterData's in-memory copy. See _on_bank_changed().
	if bank_container != null:
		var bank_cells: Variant = data.get("bank_inventory", [])
		if bank_cells is Array:
			bank_container.load_server_array(bank_cells as Array)

	var carry: Node = _get_player_inventory_container()
	if carry != null and carry.has_method("load_server_array"):
		var carry_cells: Variant = data.get("inventory", [])
		if carry_cells is Array:
			carry.load_server_array(carry_cells as Array)
	else:
		# THE DANGEROUS ONE, and the reason this is a warning rather than a
		# shrug. The server has already moved the item. If the carry grid never
		# took the new array, it is now holding the PRE-transfer layout, and the
		# next save_character_state() captures the backpack from that same grid
		# and pushes it over the server's carry_items - turning "this screen
		# could not show it" into "this item no longer exists". Same trap
		# lootbaginventory.gd guards with its `applied` check.
		push_warning("BankInventory: carry grid not found — the server moved the item, this screen did not")
		_notify("Reopen your bag — it's out of step with the server.")


func _handle_transfer_refusal(res: Dictionary, captured_player: Node) -> void:
	# NOTHING MOVED ON EITHER SIDE. The endpoint removes from the source, adds
	# to the destination, and rolls back if the add does not fit - so a refusal
	# always leaves the item exactly where it started, and the grids are already
	# correct. There is nothing to repair here, only something to say.
	var code: int = int(res.get("status", 0))

	match code:
		400:
			_notify_player(captured_player, "You don't have that many.")
		404:
			_notify_player(captured_player, "That character isn't loaded.")
		409:
			Audio.play("refused")
			_notify_player(captured_player, "No room for that.")
		_:
			_notify_player(captured_player, "No connection — try again.")

	if OS.is_debug_build():
		print("[BANK] transfer refused (%d) — %s" % [code, res.get("error", "")])


func _on_transfer_requested(source_slot: InventorySlot, _target_slot: InventorySlot) -> void:
	# The direction is decided by where the stack came FROM, not by which
	# container relayed the signal - a drag out of the bank is announced by the
	# backpack, because the backpack is what it landed on.
	if source_slot == null or source_slot.is_empty():
		return

	var op: String = "withdraw" if source_slot.slot_type == InventorySlot.BANK_SLOT_TYPE else "deposit"
	request_transfer(op, source_slot.stack.data.item_id, source_slot.stack.quantity)


func _on_bank_slot_double_clicked(slot: InventorySlot) -> void:
	if not visible or slot == null or slot.is_empty():
		return
	request_transfer("withdraw", slot.stack.data.item_id, slot.stack.quantity)


func _on_carry_slot_double_clicked(slot: InventorySlot) -> void:
	# The visibility guard is belt and braces - _wire_carry_container(false)
	# already disconnects this on close - but a stale connection here means
	# items vanishing into the bank from the field, so it is worth two lines.
	if not visible or slot == null or slot.is_empty():
		return
	request_transfer("deposit", slot.stack.data.item_id, slot.stack.quantity)


func _notify(message: String) -> void:
	_notify_player(_get_player(), message)


func _notify_player(captured_player: Node, message: String) -> void:
	# Against a CAPTURED reference, for use after an await where the player may
	# have been freed. The caller collapses a freed reference to null first:
	# GDScript checks argument types at the call boundary, so a freed object
	# fails before this function's body gets a turn.
	if is_instance_valid(captured_player) and captured_player.has_method("show_notice"):
		captured_player.show_notice(message)


func _get_player_inventory_container() -> Node:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var inv_screen: Node = hud.get("inventory_screen") if "inventory_screen" in hud else null
	if inv_screen == null:
		return null
	return inv_screen.get_node_or_null("%inventorycontainer")


# =============================================================================
# GOLD INPUT VALIDATION
# =============================================================================

func _update_gold_ui() -> void:
	# refresh the bank gold label and clear the input field.
	# called after deposit/withdraw and when the bank first opens.
	if gold_label != null:
		var banked: int = CharacterData.get_bank_gold()
		gold_label.text = "Bank Gold: %s" % GameConstants.commas(banked)
		# THE BANKED pile, not the carried one. This panel is about the gold
		# that death cannot touch, so the coin over it should be the coin that
		# pile would be paid in.
		GameConstants.apply_gold_icon(get_node_or_null("%goldicon"), banked)
	if gold_input != null:
		gold_input.text = ""


func _on_gold_input_changed(new_text: String) -> void:
	# strip non-digit characters as the player types. without this, pasting
	# "1000g" or "abc" into the field would later int() to 0 silently.
	var clean_text: String = ""
	for i in range(new_text.length()):
		if new_text[i] in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
			clean_text += new_text[i]
	if new_text == clean_text:
		return

	# keep the caret where the player was typing rather than firing it to the
	# end of the field. rejecting a character should cost them the character,
	# not their place in the number — editing the middle of "1000" used to
	# bounce the caret to the far right on every rejected keystroke.
	var removed: int = new_text.length() - clean_text.length()
	var caret: int = gold_input.caret_column - removed
	gold_input.text = clean_text
	gold_input.caret_column = clampi(caret, 0, clean_text.length())


func _on_gold_input_submitted(_text: String) -> void:
	# ENTER IS THE ENTIRE KEYBOARD PATH THROUGH THIS PANEL, so it has to be
	# able to reach both transfers. it used to call deposit unconditionally.
	#
	# that was the "type an amount, press enter, it turns into 0" bug. the
	# usual reason to be typing at a bank is to take gold back OUT, which
	# means carry gold is 0 at that exact moment. deposit clamped the typed
	# amount down to the 0 being carried, wrote that 0 back into the field on
	# the way past, and returned without moving anything. the typed amount was
	# gone, no gold had moved, and the only recovery was to retype it and go
	# click the withdraw button — the button press enter was supposed to save.
	#
	# the rule now is just "move the amount I typed, from wherever it is":
	# whichever side actually holds that much gold is the side enter uses.
	# deposit wins when both sides could cover it, which keeps enter's old
	# meaning for the common bank-my-haul case.
	var amount: int = _typed_amount()
	if amount <= 0:
		return

	var carry: int = _carry_gold()
	var banked: int = CharacterData.get_bank_gold()

	if carry >= amount:
		_on_deposit_pressed()
	elif banked >= amount:
		_on_withdraw_pressed()
	else:
		# neither side covers the full amount. move everything the fuller side
		# has instead of doing nothing — the clamp inside each handler sizes
		# it down, so "withdraw 9999" with 300 banked still hands over 300.
		if banked > carry:
			_on_withdraw_pressed()
		else:
			_on_deposit_pressed()


# =============================================================================
# GOLD DEPOSIT / WITHDRAW
# =============================================================================

func _on_deposit_pressed() -> void:
	# move gold from carry pool to account-shared bank.
	# clamps to actual carry gold so input field can't be exploited
	# (typing 999999 when you only have 50 just transfers 50).
	var p: Node = _get_player()
	if p == null:
		return

	var amount: int = _typed_amount()
	if amount <= 0:
		return

	# THE CLAMPED VALUE IS DELIBERATELY NOT WRITTEN BACK INTO THE FIELD.
	# it used to be, and that one line is what made this panel need two
	# presses. clamping to a carry gold of 0 put a literal "0" in the box, so
	# the press did nothing AND destroyed what had been typed; the next press
	# then read that "0" and also did nothing. clamp the local number, leave
	# the player's text alone, and let a successful transfer be the only thing
	# that clears the field.
	amount = mini(amount, int(p.gold))
	if amount <= 0:
		return

	if CharacterData.deposit_gold_to_bank(amount, p):
		_update_gold_ui()
		_refresh_player_currency_displays()


func _on_withdraw_pressed() -> void:
	# move gold from account-shared bank to carry pool.
	# clamps to bank balance same way deposit clamps to carry gold, and for
	# the same reason does not write that clamp back into the input field.
	var p: Node = _get_player()
	if p == null:
		return

	var amount: int = _typed_amount()
	if amount <= 0:
		return

	amount = mini(amount, CharacterData.get_bank_gold())
	if amount <= 0:
		return

	if CharacterData.withdraw_gold_from_bank(amount, p):
		_update_gold_ui()
		_refresh_player_currency_displays()


# =============================================================================
# HELPERS
# =============================================================================

func _typed_amount() -> int:
	# the input field's contents as a number, or 0 when it's empty.
	# _on_gold_input_changed() has already stripped everything that isn't a
	# digit, so int() here can't silently swallow a "50g".
	if gold_input == null or gold_input.text.is_empty():
		return 0
	return int(gold_input.text)


func _carry_gold() -> int:
	# gold in the player's pocket right now, 0 if there's no player to ask.
	var p: Node = _get_player()
	if p == null:
		return 0
	return int(p.gold)


func _get_player() -> Node:
	# resolve the player from group. cached on first call so we don't
	# re-walk the tree on every deposit/withdraw click.
	#
	# is_instance_valid() re-resolves after a death or character swap frees the
	# old node. without it the cache holds a freed instance, which is not null,
	# so every later transfer would touch a dead object instead of the player
	# standing at the chest.
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	return player


func _refresh_player_currency_displays() -> void:
	# refresh the inventory screen's gold/lusions labels after a gold transfer.
	# called after deposit/withdraw so labels reflect new totals immediately
	# without waiting for the inventory's own poll cycle.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or hud.inventory_screen == null:
		return
	if hud.inventory_screen.has_method("_update_currency_labels"):
		hud.inventory_screen._update_currency_labels()


# =============================================================================
# DRAG AND DROP — PANEL BACKGROUND
# =============================================================================
# Accepting a drag anywhere on this window keeps Godot from flipping the
# pointer to the forbidden cursor over the header, the margins, the gold row
# and the buttons — none of which are slots, but all of which sit between the
# player and the slot they're aiming at.
#
# Accept and do nothing. The drag carries a duplicate of the stack and the
# source slot is only cleared by whoever actually takes the item, so a drop
# that lands on panel furniture leaves the item exactly where it started.
# The slots and the bank grid still handle every real transfer.

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY \
		and data.has("stack") \
		and data.has("source_slot")


func _drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass
