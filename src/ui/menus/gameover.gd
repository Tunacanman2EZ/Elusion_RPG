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


func _get_current_lusions() -> int:
	# lusions are account-shared — read directly from CharacterData.
	# the value here always matches reality because it's the single source
	# of truth (no per-character lusions to get out of sync).
	return CharacterData.get_account_lusions()


# =============================================================================
# REVIVE FLOW
# =============================================================================

func _on_revive_pressed() -> void:
	# revive sequence:
	# 1. validate death state and lusions balance
	# 2. deduct lusions from account pool (atomic save)
	# 3. restore HP on the dying character's save slot (atomic save)
	# 4. set GameState.reviving so the world scene knows to teleport
	#    the player to their death position on load
	# 5. transition to world scene
	#
	# CharacterData.add_account_lusions persists to disk immediately so
	# the player can't dupe by reviving and force-quitting before next save.
	var death_state: Dictionary = GameState.death_state
	if death_state.is_empty():
		push_warning("gameover: no death_state to revive from")
		return

	var current_lusions: int = CharacterData.get_account_lusions()
	if current_lusions < revive_cost:
		print("gameover: insufficient lusions for revive")
		return

	var char_name: String = death_state.get("character_name", "")

	# step 1: deduct lusions from the account pool (writes to disk)
	CharacterData.add_account_lusions(-revive_cost)

	# step 2: restore full HP on the dying character's save slot so they
	# wake up at full health when the world scene reloads them.
	_restore_character_resources(char_name)

	# step 3: mark that we're returning from a revive — world scene checks
	# this on load to position the player at death_state.death_position
	# instead of the default spawn point.
	GameState.reviving = true
	get_tree().change_scene_to_file(world_scene_path)


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

	# HP restored to full so when player loads the character again from select,
	# they spawn at the starting area with full health (not corpse-state).
	# this is the "respawned at town with empty pockets" experience.
	slot_data["hp"] = int(slot_data.get("max_hp", 100))

	# write back to disk — atomic save protects against force-quit exploits
	CharacterData.save_character_slot(char_name, slot_data)

	print("gameover: '%s' lost carry items and carry gold (declined revive)" % char_name)
