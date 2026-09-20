# gameover.gd — displayed after the player's death animation finishes.
# offers two choices: revive (costs lusions) or return to character select.
#
# data sources:
# - GameState.death_state (in-memory): character_name, death_position, max_hp
#   set by player.gd just before this scene loads. used to identify which
#   character is dying and where to revive them.
# - CharacterData.account_data.lusions: account-shared currency pool.
#   never lost on death — survives this screen regardless of choice.
#
# the two paths:
# - revive: deduct lusions, restore full HP, mark reviving=true, reload world
# - return: clear carry gold + carry inventory (TRUE death), back to select
#
# both paths persist atomically to disk so a force-quit between scenes can't
# duplicate items or undo the lusions spend.
#
# why revive is meaningful:
# this is the consequence layer that makes the bank feel important. carry
# gold and carry items are at risk every time you go adventuring. lusions
# (premium currency) provide an out — but at a cost the player must earn.
extends Control


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# the cost in lusions to revive from this screen.
# tune up for hardcore mode, down for casual.
@export var revive_cost: int = 20

# scene paths — exposed so they can be retargeted without editing code
@export var character_select_path: String = "res://scene/ui/menus/characterselect.tscn"
@export var world_scene_path:      String = "res://scene/elusion.tscn"

# How long to wait on POST /api/character/revive. Longer than the consume
# timeout because the player is already sitting on a death screen — a moment's
# wait is fine here, and giving up early on a request that may have succeeded
# would leave them looking at a button for a revive they have paid for.
const REVIVE_TIMEOUT := 8.0

# Guards against a double-click firing two revive requests. See
# _on_revive_pressed().
var _reviving: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_update_display()
	_wire_buttons()


# =============================================================================
# INITIALIZATION HELPERS
# =============================================================================

func _wire_buttons() -> void:
	# connect both buttons to their handlers. each connection is guarded
	# against double-wiring in case signals are also bound through the
	# editor's Signals panel.
	if has_node("%revivebutton"):
		var btn: Button = $"%revivebutton"
		if not btn.pressed.is_connected(_on_revive_pressed):
			btn.pressed.connect(_on_revive_pressed)

	if has_node("%revivegoldbutton"):
		var btn: Button = $"%revivegoldbutton"
		if not btn.pressed.is_connected(_on_revive_gold_pressed):
			btn.pressed.connect(_on_revive_gold_pressed)

	if has_node("%returnbutton"):
		var btn: Button = $"%returnbutton"
		if not btn.pressed.is_connected(_on_return_pressed):
			btn.pressed.connect(_on_return_pressed)


# =============================================================================
# DISPLAY
# =============================================================================

func _update_display() -> void:
	# refresh the lusions label and the revive button state/text.
	# if the player can't afford a revive, the button is disabled so they
	# can't accidentally click an unaffordable action.
	var current_lusions: int = _get_current_lusions()

	if has_node("%lusionslabel"):
		$"%lusionslabel".text = "Lusions: %d" % current_lusions

	if has_node("%revivebutton"):
		var btn: Button = $"%revivebutton"
		btn.text = "Revive (%d Lusions)" % revive_cost
		btn.disabled = current_lusions < revive_cost

	# THE GOLD PRICE IS A SHARE, so it has to be worked out rather than printed
	# from a constant — and it is worth showing as a NUMBER. "80% of your gold"
	# is a rule; "10,304 gold" is a decision the player can actually make.
	#
	# Computed here for the label only. The server charges against the balances
	# it owns, and its answer is the one that counts; this is allowed to be a
	# few coins stale without anything going wrong.
	if has_node("%revivegoldbutton"):
		var btn: Button = $"%revivegoldbutton"
		var price: int = _gold_revive_price()
		btn.text = "Revive (%d Gold)" % price
		# Zero means an empty purse AND an empty bank, which is the one case
		# the gold route cannot cover. Nothing to take, so nothing to offer.
		btn.disabled = price <= 0


func _get_current_lusions() -> int:
	# lusions are account-shared — read directly from CharacterData.
	# the value here always matches reality because it's the single source
	# of truth (no per-character lusions to get out of sync).
	return CharacterData.get_account_lusions()


# =============================================================================
# REVIVE FLOW
# =============================================================================

func _on_revive_pressed() -> void:
	await _revive_paying_with("lusions")


func _revive_paying_with(method: String) -> void:
	# revive sequence:
	# 1. validate death state, and check the balance as a courtesy
	# 2. tell the server the character is dead, then ask it to revive them —
	#    it takes the cost and restores the resources, not this script
	# 3. copy the result into the local slot
	# 4. set GameState.reviving so the world scene knows to teleport
	#    the player to their death position on load
	# 5. transition to world scene
	var death_state: Dictionary = GameState.death_state
	if death_state.is_empty():
		push_warning("gameover: no death_state to revive from")
		return

	# A COURTESY, NOT THE RULE, whichever currency this is. The server charges
	# the cost and refuses when it cannot be paid; this only saves a round trip
	# — and says so on screen, where it used to go to a console in a debug
	# build only.
	var current_lusions: int = CharacterData.get_account_lusions()
	if method == "lusions" and current_lusions < revive_cost:
		_set_notice("You need %d lusions to revive." % revive_cost)
		return
	if method == "gold" and _gold_revive_price() <= 0:
		_set_notice("You have no gold to pay with.")
		return

	var char_name: String = death_state.get("character_name", "")

	# ONE AT A TIME. A double-click used to mean two deductions; now it would
	# mean two requests, the second answered "that character is not dead" —
	# true, confusing, and entirely avoidable.
	if _reviving:
		return
	_reviving = true
	_set_button_enabled(false)

	# THE SERVER DOES ALL THREE THINGS THAT USED TO HAPPEN HERE.
	#
	# This function used to check the balance, call add_account_lusions(-cost),
	# and write full hp/mana/stamina into the save slot itself. Every one of
	# those was a decision made on the player's machine about the only thing
	# lusions are for — so dying cost nothing that a patched client had to
	# respect, and PUT /api/account/lusions would have stored whatever balance
	# it was told anyway. POST /api/character/revive verifies the character is
	# dead against the server's own hp, takes the cost from the server's own
	# balance, and restores the maxima from the class curve.
	#
	# hp = 0 IS SENT FIRST, and it is not a formality. The server revives only
	# the dead and reads its stored hp to decide — which arrives by a debounced
	# save that may not have landed before the death animation finished. Saying
	# it explicitly makes the record true regardless, which it should be anyway:
	# the character IS dead at this moment.
	var slot: int = CharacterData.active_character_index
	await Api.put("/api/player/status", {"slot": slot, "hp": 0})

	var res: Dictionary = await Api.post("/api/character/revive",
		{"slot": slot, "pay": method}, REVIVE_TIMEOUT)

	# PAST AN AWAIT — this screen can be gone by now.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	_reviving = false

	if not res.get("ok", false):
		_set_button_enabled(true)
		_set_notice(str(res.get("error", "Could not revive.")))
		return

	# The server has already taken the cost and restored the character. Bring
	# the local copies into line rather than recomputing them, so the client
	# never disagrees with the row it was just handed.
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	if data.has("lusions"):
		CharacterData.set_account_lusions(int(data["lusions"]))
	if data.has("bank_gold"):
		CharacterData.set_bank_gold(int(data["bank_gold"]))
	# The carry purse comes back inside the status block, because gold is one of
	# the stats /api/player/status reports — the server may have taken part of
	# the price out of it before reaching for the bank.
	_apply_restored_status(char_name, data.get("status", {}))

	# mark that we're returning from a revive — world scene checks this on load
	# to position the player at death_state.death_position instead of the
	# default spawn point.
	GameState.reviving = true
	get_tree().change_scene_to_file(world_scene_path)


func _gold_revive_price() -> int:
	"""What the server will charge: a share of carry AND banked gold together.

	Banked gold is the part death cannot touch, which is exactly why it is worth
	spending here — it is the only pile still standing while you are looking at
	this screen. Carry gold is included because you still have it at this
	moment; it is only lost if you walk away."""
	var carried: int = 0
	var char_name: String = GameState.death_state.get("character_name", "")
	if char_name != "":
		var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
		carried = int(slot_data.get("gold", 0))
	var total: int = carried + CharacterData.get_bank_gold()
	if total <= 0:
		return 0
	return int(ceil(float(total) * GameConstants.REVIVE_GOLD_RATE))


func _on_revive_gold_pressed() -> void:
	await _revive_paying_with("gold")


func _apply_restored_status(char_name: String, status: Variant) -> void:
	"""Copy the revived character's resources out of the server's answer.

	FALLS BACK to the old local restore when the response carries no status
	block. By that point the cost has already been taken, so refusing to update
	the local copy would strand the player at 0 hp on a character the server
	believes is alive — the worst of both."""
	if status is Dictionary and not (status as Dictionary).is_empty():
		var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
		if not slot_data.is_empty():
			for field in ["hp", "mana", "stamina", "max_hp", "max_mana", "max_stamina", "gold"]:
				if (status as Dictionary).has(field):
					slot_data[field] = int((status as Dictionary)[field])
			CharacterData.save_character_slot(char_name, slot_data)
			return
	_restore_character_resources(char_name)


func _set_button_enabled(enabled: bool) -> void:
	if has_node("%revivebutton"):
		($"%revivebutton" as Button).disabled = not enabled


func _set_notice(message: String) -> void:
	"""Say why, on screen. The refusal used to be an OS.is_debug_build() print,
	which from the player's side is a button that does nothing and says
	nothing."""
	if has_node("%lusionslabel"):
		$"%lusionslabel".text = message
	elif OS.is_debug_build():
		print("[DEATH] %s" % message)


func _restore_character_resources(char_name: String) -> void:
	# write full HP, mana, and stamina to the character's save slot. used by
	# both revive (full resources at death position) and the return path
	# (full resources at starting area). the player node may not exist at
	# this point, so we update the slot data directly. the slot stores
	# max_mana / max_stamina (schema version 2), so we fill from those.
	var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
	if slot_data.is_empty():
		return
	slot_data["hp"]      = int(slot_data.get("max_hp", 100))
	slot_data["mana"]    = int(slot_data.get("max_mana", 0))
	slot_data["stamina"] = int(slot_data.get("max_stamina", 0))
	CharacterData.save_character_slot(char_name, slot_data)

# =============================================================================
# RETURN / TRUE DEATH FLOW
# =============================================================================

func _on_return_pressed() -> void:
	# accept death's full penalty — player loses carry items + carry gold.
	# bank items, bank gold, and lusions persist (soulbound / account-shared).
	# this is the "true death" path: the consequence that makes banking matter.
	var death_state: Dictionary = GameState.death_state
	var char_name: String = death_state.get("character_name", "")

	if char_name != "":
		_clear_carry_on_death(char_name)
		# RESOURCES COME BACK EVEN ON THE TRUE-DEATH PATH, and this call had
		# gone missing — _restore_character_resources()'s own docstring still
		# says it is "used by both revive and the return path".
		#
		# It did not matter while player.gd refilled on every scene load. It
		# does now: health persists across a load, so a character saved at 0
		# would be re-selected, spawn, and be a corpse. The penalty for dying
		# is the carry gold and the inventory cleared on the line above, which
		# is quite enough without also being unplayable.
		_restore_character_resources(char_name)

	# clear the death state and head back to character select
	GameState.death_state = {}
	GameState.reviving = false
	get_tree().change_scene_to_file(character_select_path)


func _clear_carry_on_death(char_name: String) -> void:
	# zero out the dying character's carry gold and clear their inventory.
	# writes directly to the save slot since the player node is no longer alive.
	#
	# what's LOST:   carry gold, carry inventory items
	# what SURVIVES: bank gold, bank inventory, lusions, XP, levels, skills
	#
	# the surviving stuff all lives in account_data and is NOT touched here.
	var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
	if slot_data.is_empty():
		push_warning("gameover: no save slot found for character '%s'" % char_name)
		return

	# carry gold lost — players bank gold to avoid this
	slot_data["gold"] = 0

	# carry inventory cleared — players bank items to keep them safe
	slot_data["inventory"] = []

	# HOTBAR CLEARED WITH THE ITEMS IT POINTED AT. The bar holds item ids, not
	# items, so leaving it alone left nine buttons naming potions this character
	# no longer owns — they look usable and do nothing. CharacterData had a
	# second copy of this whole function that did clear the hotbar and was never
	# called from anywhere; this is the half of it that was worth keeping.
	#
	# Written into the SAVE SLOT, not onto a player node, because by the time
	# this screen exists the world scene and its player are gone.
	# load_character_state() reads this key back on the next load.
	slot_data["hotbar_assignments"] = ["", "", "", "", "", "", "", "", ""]

	# HP restored to full so when player loads the character again from select,
	# they spawn at the starting area with full health (not corpse-state).
	# this is the "respawned at town with empty pockets" experience.
	slot_data["hp"] = int(slot_data.get("max_hp", 100))

	# write back to disk — atomic save protects against force-quit exploits
	CharacterData.save_character_slot(char_name, slot_data)

	if OS.is_debug_build():
		print("[DEATH] '%s' declined revive — carry items and gold cleared" % char_name)
