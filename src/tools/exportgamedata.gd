# exportgamedata.gd — writes res://data/gamedata.json, the single source of
# truth that BOTH the game and the Flask server read.
#
# HOW TO RUN IT: open this file in the Godot script editor and press
# Ctrl+Shift+X (File > Run). It is an EditorScript, so it only ever runs from
# the editor — it is never part of a build and never ships.
#
# WHY THIS EXISTS
# ---------------
# Moving loot rolls to the server means the server needs the game's data: every
# item's tier and type, every enemy's reward profile. That data currently lives
# in Godot resources and scenes, which Python cannot read.
#
# The obvious fix is to hand-maintain a second copy in the API repo. Do not do
# that. Two hand-maintained copies of the same numbers drift, and drift here
# means the client showing a drop the server never granted — the exact class of
# bug that has cost this project the most time. One authored source (Godot),
# one generated artifact (this JSON), one consumer on each side.
#
# WHY IT READS THROUGH THE REAL LOADER
# ------------------------------------
# A Python script could parse the .tres files directly — they are plain text.
# It would also have to replicate every default from itemdata.gd, because a
# .tres only stores fields that DIFFER from the default. smallhealthpotion.tres
# has no `tier` line at all; its tier is 1 because that is what ItemData says.
# A parser that did not know that would silently export tier 0 for most of the
# catalogue and quietly reshape every loot table in the game.
#
# ResourceLoader.load() applies those defaults for us, because it builds the
# same object the running game builds. Whatever the game sees is what gets
# written here, with nothing restated in a second place.
#
# ENEMIES USED TO BE READ BY INSTANTIATING THEIR SCENES. That never worked and
# the per-enemy print below is what caught it: every enemy came out at 50 hp and
# 20 xp, because their stats were assigned inside _ready() and instantiate()
# does not run _ready(). Worse, the editor builds a PLACEHOLDER script instance
# for a non-@tool script, so the values could not have been computed even if we
# had wanted to call into them. That is why EnemyData exists — the rewards are
# now .tres files, read exactly the same way items are.
#
# AFTER RUNNING IT: copy data/gamedata.json into the API repo (or point
# ELUSION_GAMEDATA at this one). Commit both — it is a build artifact, but it
# is the artifact the server's behaviour depends on, so it belongs in history.
@tool
extends EditorScript


# =============================================================================
# CONFIGURATION
# =============================================================================

const ITEMS_PATH := "res://data/items/"
const ENEMIES_PATH := "res://data/enemies/"
const CLASSES_PATH := "res://data/classes/"
const OUTPUT_PATH := "res://data/gamedata.json"

# Bump this when the SHAPE of the JSON changes — a renamed key, a removed
# field. The server refuses a schema it was not written for rather than
# reading a field that has quietly changed meaning.
const SCHEMA_VERSION := 1

# Mirrors ItemData.Type. Exported as names alongside the raw integers so the
# Python side can read `"type_name": "PET"` instead of hard-coding that PET
# happens to be 5 — an enum reordered in Godot would otherwise silently
# repoint every type check on the server.
#
# NOT A SCHEMA BUMP when a name is APPENDED here. SCHEMA_VERSION is about the
# shape of the JSON — a renamed key, a removed field — and a new enum member
# changes neither. Bumping it would make the server refuse to start against
# every gamedata.json already deployed, to announce a value it would have read
# correctly anyway. _type_name() below is what catches a genuine drift between
# this list and ItemData.Type, and it does so loudly.
const TYPE_NAMES := [
	"CONSUMABLE", "WEAPON", "ARMOR", "MATERIAL", "QUEST", "PET", "CURRENCY",
	"FISH",
]


# =============================================================================
# ENTRY POINT
# =============================================================================

func _run() -> void:
	# Constants first: _export_enemies() needs the pet-odds table out of them.
	var constants: Dictionary = _export_constants()
	var items: Array = _export_items()
	var enemies: Array = _export_enemies(constants)
	var classes: Array = _export_classes()

	if items.is_empty():
		push_error("exportgamedata: found no items under %s — refusing to write an empty catalogue." % ITEMS_PATH)
		return
	if enemies.is_empty():
		push_error("exportgamedata: found no enemy profiles under %s — refusing to write an empty roster." % ENEMIES_PATH)
		return
	if classes.is_empty():
		push_error("exportgamedata: found no class curves under %s — refusing to write. The server would fall back to trusting the client's max_hp." % CLASSES_PATH)
		return

	var payload: Dictionary = {
		"schema": SCHEMA_VERSION,
		"generated_at": int(Time.get_unix_time_from_system()),
		"constants": constants,
		"items": items,
		"enemies": enemies,
		"classes": classes,
	}

	if not _validate(constants, items, enemies):
		push_error("exportgamedata: validation failed — nothing written. Fix the errors above and run again.")
		return

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("exportgamedata: could not open %s for writing (%d)" % [OUTPUT_PATH, FileAccess.get_open_error()])
		return

	# Sorted keys and an indent so the file diffs cleanly in git. Without
	# this, a regenerated JSON looks like a total rewrite in every commit and
	# nobody can see what actually changed.
	file.store_string(JSON.stringify(payload, "\t", true))
	file.close()

	print("exportgamedata: wrote %s — %d items, %d enemies, %d classes" % [
		OUTPUT_PATH, items.size(), enemies.size(), classes.size(),
	])

	# Printed so the numbers can be eyeballed against the scenes before any of
	# this reaches the server. A placeholder instance reads properties fine and
	# fails only on method calls, but "fine" is worth one glance: an enemy
	# showing 0 xp and 0.0 drop chance means the read did not resolve and the
	# server would silently grant nothing for that kill.
	for cls in classes:
		print("    %-10s hp %d/+%-2d   mana %d/+%-2d   stam %d/+%d" % [
			cls["class_id"], cls["hp_base"], cls["hp_per_lvl"],
			cls["mana_base"], cls["mana_per_lvl"],
			cls["stam_base"], cls["stam_per_lvl"],
		])

	for enemy in enemies:
		if not enemy["grants_rewards"]:
			print("    %-18s hp %-5d (awards nothing — never killed)" % [
				enemy["enemy_id"], enemy["max_hp"],
			])
			continue
		print("    %-18s hp %-5d xp %-5d bag %.0f%%  tier %d  pet 1/%-5d %s" % [
			enemy["enemy_id"], enemy["max_hp"], enemy["xp_reward"],
			enemy["bag_drop_chance"] * 100.0, enemy["max_loot_tier"],
			enemy["pet_odds"], enemy["pet_drop_id"],
		])


# =============================================================================
# VALIDATION
# =============================================================================

func _validate(constants: Dictionary, items: Array, enemies: Array) -> bool:
	# EVERY ITEM ID AN ENEMY NAMES MUST ACTUALLY EXIST.
	#
	# This is here because the failure it catches is completely silent at
	# runtime. _roll_pet() checks ItemRegistry.has_item(pet_drop_id) and returns
	# false if the item is missing, so a typo'd or renamed pet id does not throw,
	# does not warn, and does not drop — it just quietly makes that pet
	# unobtainable forever. "petpoisonslimesmall" against "petpoisonsmall" is
	# five characters and an entire companion nobody can ever get.
	#
	# An export is the right place to catch it: this runs once, deliberately,
	# and can refuse to write rather than shipping a roster the server will
	# happily serve and never pay out on.
	var known: Dictionary = {}
	for item in items:
		known[item["item_id"]] = true

	var ok: bool = true

	for enemy in enemies:
		for field in ["pet_drop_id", "rare_pet_drop_id"]:
			var item_id: String = String(enemy.get(field, ""))
			if item_id == "":
				continue          # no pet is a normal, valid state
			if not known.has(item_id):
				push_error("exportgamedata: enemy '%s' has %s = '%s', but no item with that item_id exists. That pet can never drop." % [enemy["enemy_id"], field, item_id])
				ok = false

	# Gold is appended to every bag by id, through the same has_item() gate. A
	# missing one does not break the drop — it silently removes gold from every
	# loot bag in the game.
	for key in ["gold_small_id", "gold_large_id"]:
		var gold_id: String = String(constants.get(key, ""))
		if gold_id == "" or not known.has(gold_id):
			push_error("exportgamedata: constants.%s = '%s' names no existing item. Loot bags would contain no gold." % [key, gold_id])
			ok = false

	return ok


# =============================================================================
# ITEMS
# =============================================================================

func _export_items() -> Array:
	var out: Array = []
	var seen: Dictionary = {}

	for path in _find_files(ITEMS_PATH, ".tres"):
		var res: Resource = ResourceLoader.load(path)
		if res == null or not (res is ItemData):
			# Not an error — data/items/ may hold other resources later. The
			# count printed at the end is the check that matters.
			continue

		var item: ItemData = res

		if item.item_id == "":
			push_warning("exportgamedata: %s has an empty item_id — skipped." % path)
			continue

		# A duplicate item_id is a real defect, not a cosmetic one: the server
		# would index by id and one of the two would simply vanish from every
		# loot table with no error anywhere.
		if seen.has(item.item_id):
			push_error("exportgamedata: duplicate item_id '%s' in %s and %s" % [item.item_id, seen[item.item_id], path])
			continue
		seen[item.item_id] = path

		out.append({
			"item_id": item.item_id,
			"display_name": item.display_name,
			"tier": item.tier,
			"type": int(item.type),
			"type_name": _type_name(int(item.type)),
			"value": item.value,
			"stackable": item.stackable,
			"max_stack": item.max_stack,
			"required_level": item.required_level,

			# Whether an enemy may roll it at all, independent of its tier.
			# pick_weighted_item_id() has to skip a false here or a cooked fish
			# drops off a slime — see the field's own comment in itemdata.gd.
			"droppable": item.droppable,

			# THE COOKING RECIPE, because /api/cooking/cook is the thing that
			# decides what a raw fish becomes and it cannot be trusted to the
			# client - see docs/inventoryauthority.md. Exported for every item
			# rather than only for FISH: a uniform row shape means the Python
			# side reads item["cooks_into"] without first asking what type it is
			# holding, and "" is a perfectly good "not cookable".
			"cooks_into": item.cooks_into,
			"cook_level": item.cook_level,
			"cook_xp": item.cook_xp,
			"cook_mastery_level": item.cook_mastery_level,

			# What landing this fish is worth, read by /api/fishing/catch.
			"fishing_xp": item.fishing_xp,
		})

	out.sort_custom(func(a, b): return a["item_id"] < b["item_id"])
	return out


func _type_name(type_index: int) -> String:
	if type_index < 0 or type_index >= TYPE_NAMES.size():
		# An enum value with no name means ItemData.Type gained an entry that
		# TYPE_NAMES above did not. Say so loudly — a silent "UNKNOWN" would
		# end up in a loot filter on the server.
		push_error("exportgamedata: ItemData.Type value %d has no name in TYPE_NAMES — update this script." % type_index)
		return "UNKNOWN_%d" % type_index
	return TYPE_NAMES[type_index]


# =============================================================================
# ENEMIES
# =============================================================================

func _export_enemies(constants: Dictionary) -> Array:
	# Reads data/enemies/*.tres — no scene instantiation, no _ready(), no
	# placeholder script instances. Structurally identical to _export_items()
	# above, which is the point: an enemy's rewards are data now, in the same
	# sense an item's tier always was.
	var out: Array = []
	var seen: Dictionary = {}

	for path in _find_files(ENEMIES_PATH, ".tres"):
		var res: Resource = ResourceLoader.load(path)
		if res == null or not (res is EnemyData):
			continue

		var enemy: EnemyData = res

		if enemy.enemy_id == "":
			push_warning("exportgamedata: %s has an empty enemy_id — skipped." % path)
			continue

		# A duplicate id is a hard error for the same reason it is with items:
		# the server indexes by id, so one of the two would simply vanish from
		# the roster with nothing anywhere to say it had.
		if seen.has(enemy.enemy_id):
			push_error("exportgamedata: duplicate enemy_id '%s' in %s and %s" % [enemy.enemy_id, seen[enemy.enemy_id], path])
			continue
		seen[enemy.enemy_id] = path

		out.append({
			"enemy_id":          enemy.enemy_id,
			"display_name":      enemy.display_name,
			"resource":          path,
			"grants_rewards":    enemy.grants_rewards,
			"max_hp":            enemy.max_hp,
			"xp_reward":         enemy.xp_reward,
			"attack_xp_reward":  enemy.attack_xp_reward,
			"bag_drop_chance":   enemy.bag_drop_chance,
			"max_loot_tier":     enemy.max_loot_tier,
			"max_item_slots":    enemy.max_item_slots,
			"slot_fill_chance":  enemy.slot_fill_chance,
			"pet_drop_id":       enemy.pet_drop_id,
			"rare_pet_drop_id":  enemy.rare_pet_drop_id,
			"rare_pet_chance":   enemy.rare_pet_chance,
			"pet_odds_override": enemy.pet_odds_override,
			"pet_odds":          _resolve_pet_odds(enemy.pet_odds_override, enemy.max_loot_tier, constants),
		})

	out.sort_custom(func(a, b): return a["enemy_id"] < b["enemy_id"])
	return out


func _export_classes() -> Array:
	# Same shape as _export_items(). A class's curve is the last thing the client
	# gets to assert about a character: the server knows your level and your
	# class, and until this existed it still could not work out your maximum
	# health, because hp_base and hp_per_lvl were literals inside
	# warrior.gd's _set_stat_curve().
	var out: Array = []
	var seen: Dictionary = {}

	for path in _find_files(CLASSES_PATH, ".tres"):
		var res: Resource = ResourceLoader.load(path)
		if res == null or not (res is ClassData):
			continue

		var cls: ClassData = res
		if cls.class_id == "":
			push_warning("exportgamedata: %s has an empty class_id — skipped." % path)
			continue
		if seen.has(cls.class_id):
			push_error("exportgamedata: duplicate class_id '%s' in %s and %s" % [cls.class_id, seen[cls.class_id], path])
			continue
		seen[cls.class_id] = path

		out.append({
			"class_id":     cls.class_id,
			"display_name": cls.display_name,
			"hp_base":      cls.hp_base,
			"hp_per_lvl":   cls.hp_per_lvl,
			"mana_base":    cls.mana_base,
			"mana_per_lvl": cls.mana_per_lvl,
			"stam_base":    cls.stam_base,
			"stam_per_lvl": cls.stam_per_lvl,
		})

	out.sort_custom(func(a, b): return a["class_id"] < b["class_id"])
	return out


func _resolve_pet_odds(override: int, max_loot_tier: int, constants: Dictionary) -> int:
	# MIRRORS BaseEnemy.get_pet_odds(). If you change the rule there, change it
	# here — this is the one piece of logic in this file that is restated rather
	# than read, and it is restated only because a placeholder instance cannot
	# be asked to run the real thing (see _export_enemies above).
	#
	# The tier TABLE is still the real one, read out of BaseEnemy's constants a
	# few lines up, so only the two-line branch is duplicated and the numbers
	# themselves cannot drift.
	if override > 0:
		return override

	var table: Dictionary = constants.get("pet_odds_by_tier", {})
	var fallback: int = int(constants.get("pet_odds_fallback", 1296))
	return int(table.get(max_loot_tier, fallback))


# =============================================================================
# CONSTANTS
# =============================================================================

func _export_constants() -> Dictionary:
	# Read off the classes that DEFINE these so they can never disagree with
	# them. Hard-coding 100 here and changing LARGE_GOLD_THRESHOLD there is the
	# same drift this whole file exists to prevent.
	var enemy_consts: Dictionary = (load("res://src/enemies/baseenemy.gd") as GDScript).get_script_constant_map()
	var game_consts: Dictionary = (load("res://src/systems/gameconstants.gd") as GDScript).get_script_constant_map()
	var char_consts: Dictionary = (load("res://src/systems/characterdata.gd") as GDScript).get_script_constant_map()

	return {
		"large_gold_threshold": int(enemy_consts.get("LARGE_GOLD_THRESHOLD", 100)),
		"gold_small_id":        String(enemy_consts.get("GOLD_SMALL_ID", "smallamountofgold")),
		"gold_large_id":        String(enemy_consts.get("GOLD_LARGE_ID", "largeamountofgold")),
		"pet_odds_fallback":    int(enemy_consts.get("PET_ODDS_FALLBACK", 1296)),
		"pet_odds_by_tier":     enemy_consts.get("PET_ODDS_BY_TIER", {}),

		# THE XP CURVE, and the most important two numbers in this file.
		#
		# gameconstants.gd exists because this formula previously lived in two
		# places, they drifted, and the sanitizer started overwriting honest
		# saves with garbage — 1,636 XP became 52 million at level 20. The
		# server is about to become a THIRD place that needs this curve, so it
		# reads the same two numbers rather than restating the formula in
		# Python with a comment hoping someone keeps them in step.
		"xp_base":              float(game_consts.get("XP_BASE", 100.0)),
		"xp_growth":            float(game_consts.get("XP_GROWTH", 1.15)),
		"dupe_pet_lusions":     int(game_consts.get("DUPE_PET_LUSIONS", 20)),
		"revive_cost":          int(game_consts.get("REVIVE_COST", 20)),
		"cook_burn_max":        float(game_consts.get("COOK_BURN_MAX", 0.40)),
		"fishing_tier_per_level": int(game_consts.get("FISHING_TIER_PER_LEVEL", 20)),
		"skill_xp_base":        int(game_consts.get("SKILL_XP_BASE", 100)),
		"skill_xp_growth":      game_consts.get("SKILL_XP_GROWTH", {}),

		# The bank's size. Exported because the server has to agree with it:
		# it stores the bank as a positional array and rejects one that is
		# longer than capacity, so a mismatch here is a refused save rather
		# than a cosmetic difference.
		"bank_capacity":        int(char_consts.get("BANK_MAX_SLOTS", 50)),
	}


# =============================================================================
# HELPERS
# =============================================================================

func _find_files(root: String, extension: String) -> Array:
	# Recursive directory walk. Exported .pck builds do not ship .tres source
	# files, which is another reason this is editor-only.
	var found: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		push_error("exportgamedata: cannot open %s" % root)
		return found

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue

		var full: String = root.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_find_files(full, extension))
		elif entry.ends_with(extension):
			found.append(full)

		entry = dir.get_next()
	dir.list_dir_end()

	return found
