# gameover.gd — displayed after the player's death animation finishes.
# offers two choices: revive (costs lusions) or return to character select.
#
# data sources:
# - GameState.death_state (in-memory): character_name, death_position, max_hp
#   set by player.gd just before this scene loads. used to identify which
#   character is dying. A revive goes to town, not to death_position - see
#   REVIVED IN TOWN below.
# - CharacterData.account_data.lusions: account-shared currency pool.
#   never lost on death — survives this screen regardless of choice.
#
# the two paths, and BOTH OF THEM ARE SERVER CALLS NOW:
# - revive: POST /api/character/revive  — takes the price, refills the pools
# - return: POST /api/character/respawn — burns the carry gold through the
#           ledger, empties the carry bag, refills the pools
#
# The return path was local until it produced a character on 52 hp. The rule
# both halves now follow is the one in CLAUDE.md: the client sends what it DID,
# never what it now HAS. "I accepted death" is a fact. "I have full health and
# no gold" is two decisions, and decisions live on the server.
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

# The cost in lusions to revive from this screen - READ, NOT COPIED. It was an
# export holding its own 20 beside GameConstants.REVIVE_COST, which is the one
# the exporter sends the server. Retune the constant and this button would have
# gone on showing the old price while the server charged the new one.
var revive_cost: int:
	get:
		return GameConstants.REVIVE_COST

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

func _get_current_score() -> int:
	# Mirrors _get_current_lusions(), through the public accessor rather than
	# reaching into account_data and calling a private method on the autoload.
	# The first draft of this did the latter, which works and is the wrong
	# shape - the lusions path next door has had a getter for exactly this
	# reason since it was written.
	return CharacterData.get_account_score()


func _update_display() -> void:
	# refresh the lusions label and the revive button state/text.
	# if the player can't afford a revive, the button is disabled so they
	# can't accidentally click an unaffordable action.
	var current_lusions: int = _get_current_lusions()

	if has_node("%lusionslabel"):
		$"%lusionslabel".text = "Lusions: %s" % GameConstants.commas(current_lusions)

	# THE SCORE, WHICH IS THE ONE NUMBER THAT GOES UP WHEN YOU LOSE.
	#
	# READ-ONLY HERE, and deliberately not refreshed after a revive completes:
	# the figure on this screen is what death has cost you UP TO this death,
	# and the price of the one you are looking at is printed on the buttons
	# below it. Showing the post-payment total would answer a question nobody
	# is asking while they decide.
	#
	# SERVER-OWNED. /api/character/revive adds to it in the same transaction as
	# the payment; nothing on this side ever writes it, and serverstorage.gd
	# has no PUT for it. A client that could set its own score would be E-8
	# with a different column name.
	if has_node("%scorelabel"):
		$"%scorelabel".text = "Score: %d" % _get_current_score()

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
		var held: int = _gold_revive_held()
		if price > held:
			# THE FLOOR, SPELLED OUT ON THE BUTTON. Below 100 gold the price
			# is more than the player holds and the server refuses the gold
			# route outright. A button reading "Revive (100 Gold)" that greys
			# out without saying why reads as a bug; one reading "Need 100
			# Gold" is a price tag the player can act on.
			#
			# THIS BRANCH IS THE ONLY ONE THAT FIRES BELOW 100. Between 100 and
			# 123 the floor still lifts the price above the share, but it is
			# affordable, so that case takes the ordinary branch and simply
			# shows a higher number than the percentage would suggest.
			btn.text = "Need %s Gold" % GameConstants.commas(price)
			btn.disabled = true
		else:
			btn.text = "Revive (%s Gold)" % GameConstants.commas(price)
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
	# 4. back to town, at its usual spawn - see REVIVED IN TOWN below
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

	# REVIVED IN TOWN, at its usual spawn - where every login starts too.
	# This used to set GameState.reviving "so the world scene can put the
	# player back at death_state.death_position", and nothing ever read it: a
	# revive always landed in town. The owner chose town on day 1 rather than
	# building the other thing - coming back to life beside whatever killed
	# you is mostly a second death. The flag is gone so no one builds on it.
	GameState.death_state = {}
	# NOT change_scene_to_file(): that is a load() of an area's path, and a
	# load() of an area still loading in the background never returns. See
	# AreaRegistry.scene_at().
	var world: PackedScene = AreaRegistry.scene_at(world_scene_path)
	if world == null:
		push_warning("GameOver: the world scene %s did not load" % world_scene_path)
		return
	get_tree().change_scene_to_packed(world)


func _gold_revive_held() -> int:
	"""Carry plus bank, the same pair _gold_revive_price() charges against.

	SPLIT OUT so the button can compare the price to the balance without
	computing the balance a second way. Two hand-rolled copies of "carry plus
	bank" is how a button ends up disagreeing with the price printed on it."""
	var carried: int = 0
	var char_name: String = GameState.death_state.get("character_name", "")
	if char_name != "":
		var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
		carried = int(slot_data.get("gold", 0))
	return carried + CharacterData.get_bank_gold()


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
	# maxi() against the floor, mirroring gamedata.revive_gold_cost(). The
	# result CAN exceed what the player holds - that is what the floor does at
	# the bottom of the curve - and the caller is what decides whether to offer
	# the button, not this function. A price clamped to the balance here would
	# put an affordable-looking number on a button the server is going to
	# refuse.
	return maxi(GameConstants.REVIVE_GOLD_MINIMUM,
		int(ceil(float(total) * GameConstants.REVIVE_GOLD_RATE)))


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
	# THE FALLBACK, AND NOTHING ELSE CALLS IT DIRECTLY ANY MORE. Its comment
	# used to say "used by both revive and the return path", and that sentence
	# outlived both facts: revive moved to the server, and the return path has
	# now followed it. It survives for the one case _apply_restored_status()
	# describes - a 200 that carries no status block - where the server has
	# already done the work and the client just needs numbers to draw.
	#
	# It must NOT be called when a request FAILED. That is what it was doing on
	# the return path, and it is how the client came to be deciding its own hp.
	#
	# write full HP, mana, and stamina to the character's save slot. the player
	# node may not exist at this point, so we update the slot data directly.
	# the slot stores max_mana / max_stamina (schema version 2), so we fill
	# from those.
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
	#
	# THE SERVER DOES BOTH HALVES NOW, and it is the same sentence that sits
	# over _pay_and_revive(). This screen has two exits and only one of them was
	# ever migrated; this one went on writing full hp into the save slot and
	# zeroing the carry gold in the same local dictionary, and BOTH of those
	# were wrong, in opposite directions.
	#
	# THE HEAL WAS A CLIENT DECISION. So the next status push arrived at the
	# server as a rise from hp 0 to hp 504 with nothing authorising it, and
	# _reconcile_heals() clamped it to what a few seconds of regeneration could
	# produce. The log line was exact:
	#
	#     unexplained heal: hp +504 vs regen 53 + granted 0
	#     heal clamped: hp 504 -> 52
	#
	# The player came back on screen with full bars, logged out, logged back in,
	# and found a corpse on 52 hp. The reconciler was not the bug. It was the
	# only part of the system telling the truth.
	#
	# THE PENALTY WAS ALSO A CLIENT DECISION, AND IT DID NOTHING. `gold` is in
	# the server's SERVER_OWNED_STATS, so the zero written below never reached
	# it — the carry gold was still there and came back in full on the next
	# login. The empty inventory DID stick, because losing items is a loss and
	# only gains are reconciled. True death took the items, refunded the gold,
	# and left the character unplayable.
	var death_state: Dictionary = GameState.death_state
	var char_name: String = death_state.get("character_name", "")

	if char_name == "":
		GameState.death_state = {}
		get_tree().change_scene_to_file(character_select_path)
		return

	# ONE AT A TIME, the same guard the revive uses and for the same reason: a
	# double-click here used to mean two local restores, which was harmless, and
	# now means two requests, the second answered "that character is not dead" —
	# true, confusing, and avoidable.
	if _reviving:
		return
	_reviving = true

	var slot: int = CharacterData.active_character_index
	var res: Dictionary = await Api.post("/api/character/respawn",
		{"slot": slot}, REVIVE_TIMEOUT)

	# PAST AN AWAIT — this screen can be gone by now.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	_reviving = false

	if not res.get("ok", false):
		# NO LOCAL FALLBACK ON A FAILED CALL, and that is the whole point of
		# the change. Restoring here would put the character back exactly where
		# the clamp found it. Say so and let them press it again.
		_set_notice(str(res.get("error", "Could not reach the server.")))
		return

	# The server has destroyed the gold, emptied the carry bag and refilled the
	# three pools. Bring the local copies into line rather than recomputing
	# them, so the client never disagrees with the row it was just handed.
	_clear_carry_on_death(char_name)
	_apply_restored_status(char_name, res.get("data", {}).get("status", {})
		if res.get("data", {}) is Dictionary else {})

	# clear the death state and head back to character select
	GameState.death_state = {}
	get_tree().change_scene_to_file(character_select_path)


func _clear_carry_on_death(char_name: String) -> void:
	# zero out the dying character's carry gold and clear their inventory.
	# writes directly to the save slot since the player node is no longer alive.
	#
	# what's LOST:   carry gold, carry inventory items, everything worn
	# what SURVIVES: bank gold, bank inventory, lusions, XP, levels, skills
	#
	# the surviving stuff all lives in account_data and is NOT touched here.
	var slot_data: Dictionary = CharacterData.get_character_by_name(char_name)
	if slot_data.is_empty():
		push_warning("gameover: no save slot found for character '%s'" % char_name)
		return

	# carry gold lost — players bank gold to avoid this
	slot_data["gold"] = 0

	# carry inventory cleared — players bank items to keep them safe. The
	# hotbar's keys go with it: they are cells 20-29 of this same array, not a
	# separate list, which is also why there is no hotbar line here any more.
	# The server's respawn deletes every carried row, keys included.
	slot_data["inventory"] = []

	# WORN GEAR GOES WITH THE BAG. Day 2, the owner: "gear is not dropping on
	# full death" - it never had. The respawn now takes everything worn, mythic
	# weapons included; only a paid revive keeps it.
	slot_data["equipment"] = {}

	# HP IS NOT SET HERE ANY MORE, and that line is the bug this whole path was
	# rewritten for. It wrote full health into the slot on the client's own
	# authority; the server saw the next sync as an unexplained heal from zero
	# and clamped it, so the character that looked healthy on this screen was a
	# corpse on 52 hp after a relog.
	#
	# POST /api/character/respawn decides it now, and _apply_restored_status()
	# copies the answer in. Everything left in this function is a MIRROR of a
	# decision the server has already made and committed - the gold above is
	# gone from `saves` through the ledger, the bag is gone from `carry_items`,
	# the gear from `saves.equipment` - so these writes only stop the UI showing
	# stale numbers for a frame.
	#
	# write back to disk — atomic save protects against force-quit exploits
	CharacterData.save_character_slot(char_name, slot_data)

	if OS.is_debug_build():
		print("[DEATH] '%s' declined revive — carry items, gold and worn gear cleared" % char_name)
