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

# Shorter than Api.TIMEOUT (10s), longer than Api.PROBE_TIMEOUT (3s).
#
# A kill report is a request the player made — they swung, something died, and
# they are waiting to see what they got — so it deserves more patience than a
# background probe. But ten seconds of "did I get anything?" per kill is not
# patience, it is a broken-feeling game. With the server down, every kill spent
# the full ten seconds before saying so, and each one held an HTTPRequest node
# open for the duration.
const KILL_TIMEOUT := 4.0


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

	# Collapsed here because this runs before any await, but the enemy can
	# already hold a freed player reference by the time it dies — and a freed
	# object cannot be passed to a typed Node parameter at all.
	var immediate: Node = killer if is_instance_valid(killer) else null

	if not Api.is_logged_in():
		_notify(immediate, "Not connected — no reward.")
		return

	# ALREADY KNOWN TO BE DOWN — refuse now rather than in four seconds.
	#
	# Api tracks reachability from every request the game makes, so once one has
	# failed there is nothing to learn from making nine more and waiting out
	# each timeout. is_known_offline() is false until something has actually
	# asked, so this cannot refuse kills on a fresh boot that has not probed.
	#
	# It self-heals: any successful request flips the flag back, and the login
	# screen's connection banner is driven by the same signal.
	if Api.is_known_offline():
		_notify(immediate, "Server offline — no reward.")
		if OS.is_debug_build():
			print("[KILL] %s skipped — server known offline" % enemy_id)
		return

	var slot: int = CharacterData.active_character_index

	var res: Dictionary = await Api.post("/api/combat/kill", {
		"slot": slot,
		"enemy_id": enemy_id,
	}, KILL_TIMEOUT)

	# THE PLAYER MAY HAVE BEEN FREED WHILE WE WAITED, and a freed object cannot
	# be passed to a typed Node parameter — not even to a function whose first
	# line checks is_instance_valid(). GDScript validates argument types AT THE
	# CALL BOUNDARY, before the body runs, so the guard never gets a turn:
	#
	#   Invalid type in function '_notify' in base 'Node (combat.gd)'.
	#   The Object-derived class of argument 1 (previously freed) is not a
	#   subclass of the expected argument class.
	#
	# null IS legal for a typed Node parameter. A freed object is not. So the
	# reference is collapsed to null HERE, once, and every call below is safe.
	#
	# Same fix and same reasoning as pet.gd's _consume_pending_target(). It bites
	# here because a failed request waits out the full timeout, and ten seconds
	# is long enough to die, teleport, or return to character select.
	var target: Node = killer if is_instance_valid(killer) else null

	if not res.get("ok", false):
		# NO FALLBACK ROLL. Rolling locally when the server cannot be reached
		# would hand the entire exploit back: a client that can produce its own
		# loot only has to make the request fail. A kill the server did not
		# record is a kill that did not pay, and the player is told so.
		_notify(target, _refusal_text(res))
		if OS.is_debug_build():
			print("[KILL] %s refused — %s" % [enemy_id, res.get("error", "")])
		return

	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}

	_apply_xp(target, data)
	_spawn_loot_bag(data, target, at_position)

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

# killer must already be valid-or-null — see report_kill(). A freed object
# cannot reach this function's body at all.
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

	# NO BAG ID, NO BAG. The node is a picture of rows the server owns, and
	# without the id there is nothing for the panel to ask against — so the bag
	# would sit on the ground refusing every take. Spawning nothing and saying
	# why in the log is the honest version of that.
	#
	# This should be unreachable: /api/combat/kill returns an id whenever it
	# returns contents. It is here because the alternative failure mode is a
	# player standing over loot they cannot pick up, with no explanation.
	var bag_id: String = str(data.get("bag_id", ""))
	if bag_id == "":
		push_warning("Combat: kill returned contents with no bag_id — nothing spawned")
		return

	# POSITION-ALIGNED, NOT PACKED. The server stamps a position on every entry
	# and that position is the only thing /api/loot/take accepts. Appending in
	# arrival order happens to agree with it today and would stop agreeing the
	# first time an entry was skipped — and it would stop agreeing as "the
	# player took a different item than the one they clicked", silently.
	#
	# Quantities arrive as JSON numbers, which Godot parses as floats — 5 comes
	# back as 5.0, and an item stack of 5.0 is not an item stack of 5. Coerced
	# here rather than trusting whatever the bag does with it.
	var cleaned: Array = []
	for entry in contents:
		if not (entry is Dictionary):
			continue
		var cell: int = _int(entry.get("position", -1), -1)
		if cell < 0:
			push_warning("Combat: a loot entry arrived with no position — skipped")
			continue
		if cell >= cleaned.size():
			cleaned.resize(cell + 1)
		cleaned[cell] = {
			"item_id":  str(entry.get("item_id", "")),
			"quantity": maxi(_int(entry.get("quantity", 1), 1), 1),
		}

	if cleaned.is_empty():
		return

	var bag: Node = LOOTBAG_SCENE.instantiate()
	bag.global_position = at_position

	var container: Node = _resolve_loot_container()
	if container == null:
		push_warning("Combat: no container for the loot bag — not spawned")
		bag.queue_free()
		return

	container.add_child(bag)

	# Positional: a bag landing across the field should not be as loud as one
	# at your feet. Fires whether or not the player ever walks over to it —
	# it is the sound of something hitting the ground, not of you collecting it.
	Audio.play_at("bag_drop", at_position)

	# AFTER the position is set, so there is nothing to blend from. Without it
	# the bag is drawn once at the world origin and streaks to the corpse — the
	# same physics-interpolation artifact as every projectile in the game.
	bag.reset_physics_interpolation()

	# BEFORE set_contents, deliberately. The id is what makes the contents mean
	# anything — a bag holding items with no id to ask against is the one state
	# the panel cannot do anything useful with.
	if bag.has_method("set_bag_id"):
		bag.set_bag_id(bag_id)
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
		# The server's kill bucket. A player should essentially never see this —
		# it holds fifty and refills five a second, which is well past any rate
		# a real fight produces. If it starts appearing during normal play the
		# bucket is mis-sized, not the player.
		return "Kill not registered — try again."
	return "No connection — no reward."


func _notify(killer: Node, message: String) -> void:
	# The is_instance_valid() check here is NOT what protects this function —
	# by the time it runs, a freed argument has already failed the type check at
	# the call boundary. Callers must collapse a freed reference to null before
	# calling. This only handles the null they pass.
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
