# combat.gd — reports kills to the server and applies whatever comes back.
#
# Registered as an autoload, and that is the whole reason this file exists
# rather than the code living in BaseEnemy._die().
#
# NEVER AWAIT ON THE CORPSE
# -------------------------
# _die() calls queue_free() on the next line. An await inside _die() would
# suspend on a node that is about to stop existing, and Godot silently drops a
# resumed coroutine whose object has been freed — so whether the player got
# their loot would come down to whether the enemy happened to survive until the
# response landed.
#
# That is not hypothetical. BaseEnemy._spawn_loot_bag() carries a long comment
# about the same trap: a deferred call onto the dying enemy worked for every
# enemy except the small poison slime, which awaits its death animation, and
# smalls never dropped a single bag. The fix then was to defer onto the
# container instead. The fix now is the same shape — an autoload is always in
# the tree, so it can wait as long as the network takes.
#
# WHAT MOVED HERE, AND WHY IT IS LESS CODE THAN IT REPLACED
# ---------------------------------------------------------
# BaseEnemy used to own _roll_pet(), _pick_pet_id(), _build_bag_contents() and
# _pick_weighted_item_id() — about 120 lines deciding, on the player's machine,
# what a kill was worth. All four are gone. The server rolls now, with entropy
# the client never sees, and this file only renders the answer.
extends Node


const LOOTBAG_SCENE := preload("res://scene/interactables/lootbag.tscn")


# =============================================================================
# PUBLIC API
# =============================================================================

func report_kill(enemy_id: String, at_position: Vector2, killer: Node) -> void:
	# Called from BaseEnemy._die(). Deliberately returns nothing: the caller is
	# about to free itself and has no use for a result it cannot wait for.
	#
	# An empty enemy_id means this is not a payable enemy — the large poison
	# slime, which splits rather than dying and whose worth walks away as four
	# smalls. BaseEnemy.get_enemy_id() returns "" for it.
	if enemy_id == "":
		return

	if not Api.is_logged_in():
		_notify(killer, "Not connected — no reward.")
		return

	var slot: int = CharacterData.active_character_index

	var res: Dictionary = await Api.post("/api/combat/kill", {
		"slot": slot,
		"enemy_id": enemy_id,
	})

	if not res.get("ok", false):
		# NO FALLBACK ROLL. Rolling locally when the server cannot be reached
		# would hand the entire exploit back: a client that can produce its own
		# loot only has to make the request fail. A kill the server did not
		# record is a kill that did not pay, and the player is told so.
		_notify(killer, _refusal_text(res))
		if OS.is_debug_build():
			print("[KILL] %s refused — %s" % [enemy_id, res.get("error", "")])
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}

	_apply_xp(killer, data)
	_spawn_loot_bag(data, killer, at_position)

	if OS.is_debug_build():
		print("[KILL] %s — %d xp, %d item(s)%s" % [
			enemy_id,
			_int(data.get("xp_gained", 0)),
			_array(data.get("contents", [])).size(),
			"  PET!" if data.get("pet_won", false) else "",
		])


# =============================================================================
# REWARDS
# =============================================================================

func _apply_xp(killer: Node, data: Dictionary) -> void:
	# THE CLIENT RE-RUNS THE LEVEL-UP LOCALLY, AND THAT IS NOT A CONTRADICTION.
	#
	# The server has already granted the XP and committed the new level; its
	# row is the record. But the player needs the bar to move and the level-up
	# effect to fire NOW, not after the next login — so gain_xp() runs here too,
	# with the amount the server decided.
	#
	# Both sides compute from the same curve (GameConstants.xp_needed_for_level,
	# exported into gamedata.json and read by the server) on the same inputs, so
	# they land on the same number. If they ever disagree, the server's value is
	# what loads next time and the client quietly corrects itself.
	#
	# What the client no longer decides is HOW MUCH. That is the part that
	# mattered.
	if not is_instance_valid(killer):
		return

	var xp: int = _int(data.get("xp_gained", 0))
	if xp > 0 and killer.has_method("gain_xp"):
		killer.gain_xp(xp)

	var attack_xp: int = _int(data.get("attack_xp_gained", 0))
	if attack_xp > 0 and killer.has_method("gain_attack_xp"):
		killer.gain_attack_xp(attack_xp)


func _spawn_loot_bag(data: Dictionary, killer: Node, at_position: Vector2) -> void:
	var contents: Array = _array(data.get("contents", []))
	if contents.is_empty():
		return

	# Quantities arrive as JSON numbers, which Godot parses as floats — 5 comes
	# back as 5.0, and an item stack of 5.0 is not an item stack of 5. Coerced
	# here rather than trusting whatever the bag does with it.
	var cleaned: Array = []
	for entry in contents:
		if entry is Dictionary:
			cleaned.append({
				"item_id":  str(entry.get("item_id", "")),
				"quantity": maxi(_int(entry.get("quantity", 1), 1), 1),
			})

	var bag: Node = LOOTBAG_SCENE.instantiate()
	bag.global_position = at_position

	var container: Node = _resolve_loot_container()
	if container == null:
		push_warning("Combat: no container for the loot bag — not spawned")
		bag.queue_free()
		return

	container.add_child(bag)

	# AFTER the position is set, so there is nothing to blend from. Without it
	# the bag is drawn once at the world origin and streaks to the corpse — the
	# same physics-interpolation artifact as every projectile in the game.
	bag.reset_physics_interpolation()

	if bag.has_method("set_contents"):
		bag.set_contents(cleaned)
	if bag.has_method("set_owner_player"):
		bag.set_owner_player(killer)
	if bag.has_method("set_has_pet"):
		bag.set_has_pet(bool(data.get("pet_won", false)))


func _resolve_loot_container() -> Node:
	# Y-sorted world first, so bags sort with characters.
	#
	# Safe to resolve at call time here, unlike in BaseEnemy where it had to
	# happen before the enemy left the tree — an autoload is always in the tree,
	# so get_tree() is always valid.
	var container: Node = get_tree().get_first_node_in_group("lootbags")
	if container == null:
		container = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	return container


# =============================================================================
# HELPERS
# =============================================================================

func _refusal_text(res: Dictionary) -> String:
	# A 429 is the kill rate limit, which an honest player can hit on a lag
	# spike. Saying "too fast" to someone who was not going fast is worse than
	# saying nothing useful, so it gets its own wording.
	if _int(res.get("status", 0)) == 429:
		return "Kill not registered — try again."
	return "No connection — no reward."


func _notify(killer: Node, message: String) -> void:
	if is_instance_valid(killer) and killer.has_method("show_notice"):
		killer.show_notice(message)


func _int(value: Variant, fallback: int = 0) -> int:
	# JSON has no integer type, so every number Godot parses is a float. See
	# serverstorage.gd's header for the day this cost.
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		_:
			return fallback


func _array(value: Variant) -> Array:
	return value if value is Array else []
