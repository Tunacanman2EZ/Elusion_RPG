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
# the HUD listens to this for cleanup hooks.
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
	# - text_submitted: pressing enter defaults to deposit
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


# =============================================================================
# PUBLIC API — OPEN / CLOSE
# =============================================================================

func open_bank() -> void:
	# fresh load from disk in case another character/session updated the bank
	# between opens. without this, a player who swapped to another character,
	# modified the bank, and swapped back would see stale data.
	CharacterData.load_data()

	_load_bank_contents()
	_update_gold_ui()
	_center_window()

	visible = true

	# force inventory open so player can drag items between bank and carry
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_inventory"):
		hud.show_inventory()


func close_bank() -> void:
	# persist bank state before hiding (crash-safe — even if the player
	# alt-F4s right after this, the bank is already on disk).
	_save_bank_contents()
	visible = false
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
	_save_bank_contents()


# =============================================================================
# GOLD INPUT VALIDATION
# =============================================================================

func _update_gold_ui() -> void:
	# refresh the bank gold label and clear the input field.
	# called after deposit/withdraw and when the bank first opens.
	if gold_label != null:
		gold_label.text = "Bank Gold: %d" % CharacterData.get_bank_gold()
	if gold_input != null:
		gold_input.text = ""


func _on_gold_input_changed(new_text: String) -> void:
	# strip non-digit characters as the player types. without this, pasting
	# "1000g" or "abc" into the field would later int() to 0 silently.
	var clean_text: String = ""
	for i in range(new_text.length()):
		if new_text[i] in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
			clean_text += new_text[i]
	if new_text != clean_text:
		gold_input.text = clean_text
		gold_input.caret_column = clean_text.length()


func _on_gold_input_submitted(_text: String) -> void:
	# pressing enter in the input field defaults to deposit.
	# (more common action — withdraw requires explicit button click.)
	_on_deposit_pressed()


# =============================================================================
# GOLD DEPOSIT / WITHDRAW
# =============================================================================

func _on_deposit_pressed() -> void:
	# move gold from carry pool to account-shared bank.
	# clamps to actual carry gold so input field can't be exploited
	# (typing 999999 when you only have 50 just transfers 50).
	var p: Node = _get_player()
	if p == null or gold_input.text.is_empty():
		return

	var amount: int = int(gold_input.text)
	if amount <= 0:
		return

	var carry_gold: int = int(p.gold)
	if amount > carry_gold:
		amount = carry_gold
		gold_input.text = str(amount)
	if amount <= 0:
		return

	if CharacterData.deposit_gold_to_bank(amount, p):
		_update_gold_ui()
		_refresh_player_currency_displays()


func _on_withdraw_pressed() -> void:
	# move gold from account-shared bank to carry pool.
	# clamps to bank balance same way deposit clamps to carry gold.
	var p: Node = _get_player()
	if p == null or gold_input.text.is_empty():
		return

	var amount: int = int(gold_input.text)
	if amount <= 0:
		return

	var bank_balance: int = CharacterData.get_bank_gold()
	if amount > bank_balance:
		amount = bank_balance
		gold_input.text = str(amount)
	if amount <= 0:
		return

	if CharacterData.withdraw_gold_from_bank(amount, p):
		_update_gold_ui()
		_refresh_player_currency_displays()


# =============================================================================
# HELPERS
# =============================================================================

func _get_player() -> Node:
	# resolve the player from group. cached on first call so we don't
	# re-walk the tree on every deposit/withdraw click.
	if player == null:
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
