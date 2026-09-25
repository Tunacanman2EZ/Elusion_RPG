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
const SHOPS_PATH := "res://data/shops/"
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

# ItemData.RestoreTarget, in its own order. Same job as TYPE_NAMES: the server
# reads the NAME, so inserting a value into that enum renumbers the integers
# and this list is the thing that has to be updated with it. _restore_target_name()
# fails loudly rather than inventing an "UNKNOWN" that would sail into a heal
# comparison and quietly stop matching anything.
const RESTORE_TARGET_NAMES := [
	"NONE", "HP", "MANA", "STAMINA",
]

# ItemData.EquipSlot, in its own order, for the third time and for the same
# reason — with one extra motive, because this one had already gone wrong
# before the list existed.
#
# app.py was written against a slot vocabulary typed from memory: weapon, helm,
# chest, ROBE, legs, shield, ring, amulet. That has a slot the enum has never
# had and is missing BOOTS, which it does. Nothing would have errored; the
# server would simply have refused every pair of boots in the game and happily
# stored a "robe" no client could ever ask for.
#
# So the names are EXPORTED now. There is one list, it lives next to the enum
# it mirrors, and _equip_slot_name() below refuses the export if ItemData gains
# a slot this does not know — rather than letting a server hold a private copy
# that drifts in silence.
const EQUIP_SLOT_NAMES := [
	"NONE", "WEAPON", "HELM", "CHEST", "LEGS", "BOOTS", "SHIELD", "RING",
	"AMULET",
]

# Everything _fail() and _warn() have said this run.
#
# WHY COUNTERS AND NOT JUST push_error(). Two reasons, and the second is the
# one that actually bit.
#
# First, restore_amount / restore_target are checked in _export_items(), where
# the ItemData is still open, because they are not in the exported rows - the
# server does not read them. A verdict found there has to reach _validate(),
# which is the thing that decides whether to write.
#
# Second, and worse: push_error() and push_warning() render in the DEBUGGER
# panel, while print() renders in OUTPUT. The export summary is printed, so a
# clean-looking Output pane says nothing whatsoever about whether the checks
# passed - the boss's decorative pet odds were flagged on the very first run
# and went unread, because the warning was in a tab nobody had open. A check
# that reports somewhere you are not looking is not a check. So the verdict is
# printed alongside the summary, in the pane that is actually being read.
#
# AND THE COUNT IS NOT THE MESSAGE. The paragraph above was written after the
# tally went unread, and it only moved the TALLY. The text stayed in the
# Debugger, and the summary line ended "open Debugger > Errors to read them" -
# which sent someone to a panel that, for a @tool script run from the editor,
# is EMPTY. Godot fills Debugger > Errors from a running game session;
# push_warning() out of an editor tool does not appear there. So the run
# reported "8 warning(s)" and there was nowhere to read the eight.
#
# That is the same mistake one layer along, and worse than the original: the
# first version pointed at nothing, this one pointed at nothing CONFIDENTLY.
# The messages are now kept and printed with the summary. push_warning() stays
# because it is correct when this runs with a debugger attached, but nothing
# depends on anyone seeing it.
var _errors: int = 0
var _warnings: int = 0

# The text of every verdict this run, in the order it was reached, already
# prefixed for printing. Kept rather than counted so the summary can show what
# was actually wrong - see the note above about where the messages went.
var _verdicts: Array[String] = []

# Items whose icon did not resolve. Collected during the item pass, where the
# ItemData is open, and reported once at the end - see _check_icon().
var _iconless: Array = []


func _fail(message: String) -> void:
	push_error("exportgamedata: " + message)
	_errors += 1
	_verdicts.append("      ERROR    " + message)


func _warn(message: String) -> void:
	push_warning("exportgamedata: " + message)
	_warnings += 1
	_verdicts.append("      warning  " + message)


func _print_verdicts() -> void:
	# Wrapped, because the Output pane does not soft-wrap: a long verdict runs
	# off the side, and the end of the sentence is the half that says what to do
	# about it. 84 characters of message, 99 with the 15-character prefix, which
	# fits without the pane scrolling sideways at a normal editor width.
	#
	# Continuations are indented under the message rather than to the left
	# margin, so a wrapped verdict still reads as one entry instead of as two.
	for line in _verdicts:
		var indent: String = "               "
		var prefix: String = line.substr(0, 15)
		var body: String = line.substr(15)
		var out: String = prefix
		var width: int = 0
		for word in body.split(" ", false):
			if width > 0 and width + word.length() + 1 > 84:
				print(out)
				out = indent
				width = 0
			if width > 0:
				out += " "
				width += 1
			out += word
			width += word.length()
		if width > 0 or out.strip_edges() != "":
			print(out)


# =============================================================================
# ENTRY POINT
# =============================================================================

func _run() -> void:
	# Constants first: _export_enemies() needs the pet-odds table out of them.
	_errors = 0
	_warnings = 0
	_verdicts.clear()
	_iconless.clear()
	var constants: Dictionary = _export_constants()
	var items: Array = _export_items()
	var enemies: Array = _export_enemies(constants)
	# After the rows exist, because resolving a scene to an enemy needs the list
	# of enemy_ids that were actually exported - a scene whose name matches no
	# real enemy must resolve to nothing rather than to a guess.
	_annotate_placement(enemies)
	var classes: Array = _export_classes()
	var shops: Array = _export_shops(items)

	if items.is_empty():
		_fail("found no items under %s — refusing to write an empty catalogue." % ITEMS_PATH)
		return
	if enemies.is_empty():
		_fail("found no enemy profiles under %s — refusing to write an empty roster." % ENEMIES_PATH)
		return
	if classes.is_empty():
		_fail("found no class curves under %s — refusing to write. The server would fall back to trusting the client's max_hp." % CLASSES_PATH)
		return

	var payload: Dictionary = {
		"schema": SCHEMA_VERSION,
		"generated_at": int(Time.get_unix_time_from_system()),
		"constants": constants,
		"items": items,
		"enemies": enemies,
		"classes": classes,
		"shops": shops,
	}

	if not _validate(constants, items, enemies, classes):
		# Printed as well as pushed, for the same reason the verdict below is:
		# an export that refuses to write and says so only in the Debugger looks
		# from Output like an export that simply did not run.
		print("exportgamedata: REFUSED TO WRITE — %d error(s), %d warning(s):" % [_errors, _warnings])
		_print_verdicts()
		print("exportgamedata: nothing written. Fix the errors above and run again.")
		push_error("exportgamedata: validation failed — nothing written. Fix the errors above and run again.")
		return

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open %s for writing (%d)" % [OUTPUT_PATH, FileAccess.get_open_error()])
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
		# An empty pet_drop_id printed as-is is just trailing whitespace, which
		# looks identical to a pet whose name happens to be off the end of the
		# line. Say it.
		var pet_label: String = String(enemy["pet_drop_id"])
		if pet_label == "":
			pet_label = "(no pet — odds unused)"
		elif String(enemy["rare_pet_drop_id"]) != "":
			pet_label += " / %s @ %.0f%%" % [
				enemy["rare_pet_drop_id"], enemy["rare_pet_chance"] * 100.0,
			]

		print("    %-18s hp %-5d xp %-5d bag %.0f%%  tier %d  pet 1/%-5d %s" % [
			enemy["enemy_id"], enemy["max_hp"], enemy["xp_reward"],
			enemy["bag_drop_chance"] * 100.0, enemy["max_loot_tier"],
			enemy["pet_odds"], pet_label,
		])

	# Last, and after the write, because it is a headcount rather than a verdict
	# — it reports on data that just passed. Printing it from inside _validate()
	# put it above the "wrote ..." line, which read like a complaint about the
	# export instead of a note about the catalogue.
	_report_reachability(items, enemies)
	_report_unplaced_enemies()
	_report_iconless()

	# THE VERDICT, IN THE PANE YOU ARE READING. Errors cannot be non-zero here —
	# _validate() would have returned before the write — so this line is really
	# about the warnings, which are the ones that do not stop anything and are
	# therefore the ones that get missed.
	if _warnings == 0:
		print("    validation: clean.")
	else:
		print("    validation: %d warning(s) — each one below." % _warnings)
		_print_verdicts()


# =============================================================================
# VALIDATION
# =============================================================================

func _validate(constants: Dictionary, items: Array, enemies: Array, classes: Array) -> bool:
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

	# Collected across the loop and reported as ONE line — see the note at the
	# emit site below for why this is not seven.
	#
	# PackedStringArray rather than Array[String] because String.join() takes a
	# PackedStringArray, and an Array[String] is not one.
	var odds_without_pet := PackedStringArray()

	for enemy in enemies:
		for field in ["pet_drop_id", "rare_pet_drop_id"]:
			var item_id: String = String(enemy.get(field, ""))
			if item_id == "":
				continue          # no pet is a normal, valid state
			if not known.has(item_id):
				_fail("enemy '%s' has %s = '%s', but no item with that item_id exists. That pet can never drop." % [enemy["enemy_id"], field, item_id])

		# ODDS WITH NOTHING BEHIND THEM. roll_pet() reads pet_drop_id FIRST and
		# returns false on an empty one, before it ever looks at pet_odds — so an
		# enemy that grants rewards, carries a pet rate, and names no pet has a
		# roll that cannot pay out. Nothing is broken; the number is simply
		# decorative, and the export line reads "pet 1/216" as though it were not.
		#
		# A WARNING RATHER THAN AN ERROR because "no pet authored yet" is a real
		# and temporary state — it is exactly where the boss sits today, and
		# refusing to export over it would block the game on an item that has not
		# been drawn. The moment the .tres exists this goes quiet on its own.
		#
		# Skipped for an enemy that grants no rewards at all: the large slime
		# splits rather than dying, so none of its reward fields mean anything and
		# saying so every export would be noise.
		if bool(enemy.get("grants_rewards", false)) \
				and int(enemy.get("pet_odds", 0)) > 0 \
				and String(enemy.get("pet_drop_id", "")) == "":
			odds_without_pet.append(String(enemy["enemy_id"]))

	# ONE LINE FOR ALL OF THEM, NOT ONE EACH, and the count is the reason.
	#
	# Every boss in the game is in this state — seven of them — so emitted per
	# enemy this check produced seven of the run's eight warnings. A tally that
	# is seven-eighths one known, accepted, already-reported fact trains you to
	# ignore the tally, which is precisely how the FIRST instance of this went
	# unread. A check that drowns out the other checks is not doing its job
	# either.
	#
	# Already-reported is meant literally: the enemy table printed above each
	# run ends "(no pet — odds unused)" on exactly these rows, so the detail is
	# on screen already and this line only needs to say how many and which.
	if not odds_without_pet.is_empty():
		_warn("%d enemies carry pet odds with no pet_drop_id, so roll_pet() returns before it reads the rate and the odds are decorative: %s. Harmless while the pets are unauthored; each goes quiet when its .tres exists." % [
			odds_without_pet.size(), ", ".join(odds_without_pet),
		])

	# Gold is appended to every bag by id, through the same has_item() gate. A
	# missing one does not break the drop — it silently removes gold from every
	# loot bag in the game.
	for key in ["gold_small_id", "gold_large_id"]:
		var gold_id: String = String(constants.get(key, ""))
		if gold_id == "" or not known.has(gold_id):
			_fail("constants.%s = '%s' names no existing item. Loot bags would contain no gold." % [key, gold_id])

	_validate_recipes(items, known)
	_validate_skill_curves(constants)
	_validate_equipment(items, classes)

	# Every check above reports through _fail(), including the restore checks
	# run back in _export_items(). One counter, one verdict.
	return _errors == 0


func _validate_equipment(items: Array, classes: Array) -> void:
	# THE GEAR CHECKS EXIST BECAUSE EVERY ONE OF THEM FAILS WITHOUT A SOUND.
	#
	# Equipment is a slot name pointing at a bag item. Nothing about that throws:
	# a weapon with no damage equips, a piece gated on a class that does not
	# exist can never be worn by anybody, and a helmet filed under CHEST simply
	# occupies the wrong square. The player's only symptom is that their gear
	# does nothing, or that a slot they can see refuses everything they own.
	#
	# The one that actually happened: the whole cloth line — hood, robe,
	# trousers, slippers, five tiers each — was authored one slot too high, so a
	# mage's hood was a chest piece, their robe was leg armour and their
	# slippers were a shield. Twenty files, no error anywhere, and it would have
	# surfaced as "mages cannot wear helmets" long after anyone remembered why.
	var class_ids: Dictionary = {}
	for cls in classes:
		class_ids[String(cls.get("class_id", ""))] = true

	for item in items:
		var item_id: String = String(item.get("item_id", ""))
		var slot: String = String(item.get("equip_slot_name", "NONE"))
		var type_name: String = String(item.get("type_name", ""))

		# A CLASS GATE NAMING NO CLASS locks the item away from everyone. There
		# is no fallback reading — an empty list already means "anyone", so a
		# non-empty one that matches nobody cannot have been intended.
		for class_id in item.get("required_classes", []):
			if not class_ids.has(String(class_id)):
				_fail("'%s' requires class '%s', which no .tres under %s defines. Nobody can ever equip it." % [
					item_id, String(class_id), CLASSES_PATH,
				])

		if slot == "NONE":
			# TYPED AS GEAR, WEARABLE NOWHERE. Warned rather than failed: a
			# trophy filed as ARMOR to keep it out of the loot tables is a real
			# thing to want, and bushamulet is exactly that today.
			if type_name in ["WEAPON", "ARMOR"]:
				_warn("'%s' is a %s with no equip_slot — it can be owned and sold, never worn." % [item_id, type_name])
			continue

		# A WEAPON THAT HITS FOR NOTHING. Once combat reads the equipped
		# weapon's damage, a zero here is indistinguishable from being unarmed,
		# and the player has just paid for it.
		if slot == "WEAPON":
			if int(item.get("damage", 0)) <= 0:
				_fail("'%s' occupies the WEAPON slot with damage = %d — equipping it would be the same as holding nothing." % [
					item_id, int(item.get("damage", 0)),
				])
		elif int(item.get("armor_value", 0)) <= 0:
			# The defensive half of the same mistake. A warning, because a
			# cosmetic or utility piece with no armour is a legitimate design
			# and this is the door it would come through.
			_warn("'%s' occupies the %s slot but has armor_value = 0 — wearing it changes nothing." % [item_id, slot])

		# GEAR THAT IS NOT TYPED AS GEAR. type drives the loot filters and the
		# consume handler; a slotted item typed MATERIAL would be equippable and
		# also a crafting ingredient, which is not a combination anything here
		# is built to survive.
		if not (type_name in ["WEAPON", "ARMOR"]):
			_fail("'%s' occupies the %s slot but is type %s — only WEAPON and ARMOR are equipment." % [
				item_id, slot, type_name,
			])


func _validate_recipes(items: Array, known: Dictionary) -> void:
	# THE COOKING RECIPES, CHECKED THE SAME WAY THE PET IDS ARE, because they
	# fail the same way: /api/cooking/cook looks cooks_into up in ITEMS and
	# answers "that cannot be cooked" when it is missing. The fish is still
	# catchable, still sits in the bag, and simply has no use — with nothing
	# anywhere saying why. Five characters in an item_id is an entire branch of
	# the fishing skill nobody can finish.

	var by_id: Dictionary = {}
	for item in items:
		by_id[item["item_id"]] = item

	for item in items:
		var recipe: String = String(item.get("cooks_into", ""))
		var is_fish: bool = String(item.get("type_name", "")) == "FISH"

		if recipe == "":
			# Not cookable. Fine for everything that is not a fish; for a fish
			# it is probably an oversight, but a deliberately useless catch is a
			# legitimate design so this warns rather than refusing.
			if is_fish:
				_warn("FISH '%s' has no cooks_into — it can be caught but never cooked." % item["item_id"])
			continue

		if not known.has(recipe):
			_fail("'%s' cooks into '%s', but no item with that item_id exists. That fish can never be cooked." % [item["item_id"], recipe])
			continue

		# WHAT IT COOKS INTO HAS TO BE EDIBLE. The whole point of the raw/cooked
		# split is that the cooked one is a Type.CONSUMABLE the use-handler can
		# route by restore_target. Cooking a fish into another FISH, or into a
		# MATERIAL, produces something that goes in the bag and does nothing.
		var output: Dictionary = by_id[recipe]
		if String(output.get("type_name", "")) != "CONSUMABLE":
			_fail("'%s' cooks into '%s', which is %s rather than CONSUMABLE. The result would be inedible." % [item["item_id"], recipe, output.get("type_name", "?")])

		# A COOKED FISH MUST NOT BE MOB LOOT. The FISH type keeps the raw ones
		# out of the drop tables, but a cooked fish is a CONSUMABLE exactly like
		# a potion and the type filter cannot see it — that is what droppable is
		# for. Left true, every fish worth catching also falls out of the nearest
		# slime and the skill has no point. See ItemData.droppable.
		if bool(output.get("droppable", true)):
			_warn("'%s' is a cooking output but still droppable — mobs will drop it, which undercuts fishing. Set droppable = false on it." % recipe)

		# BURN CHANCE SLIDES FROM cook_level TO cook_mastery_level. Inverted, the
		# span is negative and burn_chance() answers 0.0 for every level, so the
		# fish silently never burns and the cooking skill stops mattering for it.
		var floor_level: int = int(item.get("cook_level", 1))
		var mastery: int = int(item.get("cook_mastery_level", 1))
		if mastery < floor_level:
			_fail("'%s' has cook_mastery_level %d below cook_level %d. It would never burn." % [item["item_id"], mastery, floor_level])

		if is_fish and int(item.get("fishing_xp", 0)) <= 0:
			_fail("FISH '%s' awards no fishing_xp. It can be caught but trains nothing." % item["item_id"])


func _validate_skill_curves(constants: Dictionary) -> void:
	# THE SERVER LEVELS THESE TWO NOW, off this table. A missing entry does not
	# throw — gamedata.py falls back to 1.18 — so the skill quietly climbs on a
	# curve nobody chose, and the client's own bar disagrees with the level the
	# server hands back.
	var growth: Dictionary = constants.get("skill_xp_growth", {})

	for skill in ["fishing", "cooking"]:
		if not growth.has(skill):
			_fail("constants.skill_xp_growth has no '%s'. The server would level it on a fallback curve." % skill)

	# A factor at or below 1 makes each level cost the same or LESS than the
	# last, so one grant can cascade through dozens of levels. apply_xp() caps
	# the loop at 200 to stop the worker spinning, which turns a data mistake
	# into a player at level 200 rather than an error.
	for skill in growth.keys():
		if float(growth[skill]) <= 1.0:
			_fail("skill_xp_growth['%s'] is %s. A factor at or below 1.0 makes levels cheaper as you climb." % [skill, growth[skill]])

	if int(constants.get("skill_xp_base", 0)) <= 0:
		_fail("constants.skill_xp_base must be positive.")

	var burn: float = float(constants.get("cook_burn_max", -1.0))
	if burn < 0.0 or burn > 1.0:
		_fail("constants.cook_burn_max is %s — it is a probability and must be 0..1." % burn)

	if int(constants.get("fishing_tier_per_level", 0)) < 1:
		_fail("constants.fishing_tier_per_level must be at least 1.")

	# A RATE OF ZERO IS NOT A VALID TUNING, IT IS A DISABLED SINK. There would
	# then be nothing in the game destroying gold, and supply would climb
	# without bound with nothing in the export to say it had stopped. If the tax
	# is ever meant to be switched off that should be a deliberate edit here,
	# not a 0.0 that reads like any other number.
	var tax: float = float(constants.get("kingdom_tax_rate", -1.0))
	if tax <= 0.0 or tax >= 1.0:
		_fail("constants.kingdom_tax_rate is %s — it is a fraction and must be above 0 and below 1." % tax)

	if int(constants.get("kingdom_tax_minimum", 0)) < 1:
		_fail("constants.kingdom_tax_minimum must be at least 1, or small trades are untaxed and splitting a big one avoids the sink entirely.")


func _report_iconless() -> void:
	if _iconless.is_empty():
		return
	_iconless.sort()
	var shown := PackedStringArray()
	for item_id in _iconless.slice(0, 8):
		shown.append(String(item_id))
	var line: String = "      " + ", ".join(shown)
	if _iconless.size() > shown.size():
		line += ", ..."
	print("    %d item(s) have no icon and will render as an empty cell:" % _iconless.size())
	print(line)


func _annotate_placement(enemies: Array) -> void:
	# Write placed_count onto every exported enemy row.
	#
	# WHAT THE SERVER DOES WITH IT. /api/combat/kill cannot see the fight, so the
	# only honest question left is whether this many kills could physically have
	# happened: an enemy that exists three times, on a respawner, cannot be
	# killed more than three times per respawn however loudly a client insists.
	# That ceiling is the world's, not a number somebody picked, and only Godot
	# can see the world - which is why it is computed here and shipped rather
	# than guessed at server-side.
	#
	# AN UNDERCOUNT REFUSES HONEST PLAYERS; an overcount only loosens the
	# ceiling. Every fallback below therefore errs towards counting MORE, and
	# anything that cannot be resolved at all is left at zero, which the server
	# reads as "do not judge this one" rather than as "impossible".
	#
	# TWO WAYS TO NAME AN ENEMY SCENE, because this project has two shapes of
	# them. The thin elemental variants (fireboss.tscn and its thirty-odd
	# siblings) name their EnemyData directly, which is exact. The five original
	# full scenes - bushmage, bushsniper, electricsprite, firesprite, poisonslime
	# - name a SCRIPT and no resource at all, which is what the note on
	# _report_unplaced_enemies() means by nothing connecting a scene to its data.
	# For those the filename is used, and only when it matches an enemy_id that
	# was actually exported, so a typo resolves to nothing instead of to the
	# wrong enemy.
	#
	# Validated against this project before it was written: the two paths
	# together resolve 40 of 42 enemy scenes and find 35 placed instances, which
	# is exactly the number of enemy nodes in field.tscn counted independently.
	# The two that do not resolve are bossenemy.tscn, a base other scenes inherit
	# from and nothing places directly, and poisonslime.tscn, whose enemy_id is
	# poisonslimelarge - and that one awards nothing, so its count is never read.
	var known: Dictionary = {}
	for row in enemies:
		known[String(row.get("enemy_id", ""))] = true

	var enemy_scenes: Array = _find_files("res://scene/enemy/", ".tscn")
	var scene_to_enemy: Dictionary = {}
	var unresolved: Array = []

	for scene_path in enemy_scenes:
		var file := FileAccess.open(scene_path, FileAccess.READ)
		if file == null:
			continue
		var text: String = file.get_as_text()
		file.close()

		var enemy_id: String = ""

		# 1. The EnemyData the scene names, when it names one.
		var marker: String = "res://data/enemies/"
		var at: int = text.find(marker)
		if at != -1:
			var tres_at: int = text.find(".tres", at)
			if tres_at != -1:
				enemy_id = text.substr(at + marker.length(), tres_at - at - marker.length())

		# 2. Otherwise the SCRIPT's ENEMY_DATA constant, which is how the five
		#    original full scenes name their data - bossenemy.gd line 38 is
		#    `const ENEMY_DATA := preload("res://data/enemies/boss.tres")`, and
		#    BaseEnemy falls back to it when the scene leaves enemy_data null.
		#
		#    THE CONSTANT, NOT THE FIRST PATH IN THE FILE. poisonslime.gd
		#    preloads SMALL_DATA and LARGE_DATA, in that order, so "the first
		#    res://data/enemies/ in the script" would resolve the LARGE slime's
		#    scene to the SMALL slime's id and put the ceiling on the wrong
		#    enemy. Anchoring to ENEMY_DATA leaves that scene unresolved, which
		#    is the correct answer for it.
		#
		#    This is what the filename alone got wrong: bossenemy.tscn holds
		#    the enemy whose id is "boss", so the base boss - 700 xp, the
		#    highest in the field set - was counted as placed nowhere and
		#    therefore exempted from the ceiling entirely.
		if not known.has(enemy_id):
			enemy_id = _enemy_id_from_scripts(text, known)

		# 3. Otherwise the filename, and only if it names a real enemy.
		if not known.has(enemy_id):
			var stem: String = String(scene_path).get_file().get_basename()
			enemy_id = stem if known.has(stem) else ""

		if enemy_id == "":
			unresolved.append(String(scene_path).get_file())
		else:
			scene_to_enemy[scene_path] = enemy_id

	# Every .tscn that is not itself an enemy, counted for instances of each.
	var counts: Dictionary = {}
	for world_path in _find_files("res://scene/", ".tscn"):
		if world_path.begins_with("res://scene/enemy/"):
			continue
		var world := FileAccess.open(world_path, FileAccess.READ)
		if world == null:
			continue
		var world_text: String = world.get_as_text()
		world.close()

		for scene_path in scene_to_enemy.keys():
			var n: int = _count_instances(world_text, String(scene_path))
			if n > 0:
				var eid: String = String(scene_to_enemy[scene_path])
				counts[eid] = int(counts.get(eid, 0)) + n

	for row in enemies:
		row["placed_count"] = int(counts.get(String(row.get("enemy_id", "")), 0))

	var total: int = 0
	for eid in counts.keys():
		total += int(counts[eid])
	print("    placement: %d enemy instances across %d types (the server's kill ceiling)"
		% [total, counts.size()])
	if not unresolved.is_empty():
		unresolved.sort()
		var names := PackedStringArray()
		for scene_name in unresolved:
			names.append(String(scene_name))
		# Not a warning: both known cases are benign and saying so every export
		# would train you to skip the line. It is printed because an entry here
		# that is NOT one of those two is an enemy the ceiling cannot protect.
		print("      (%d scene(s) map to no enemy_id, so they are left uncounted: %s)"
			% [unresolved.size(), ", ".join(names)])


func _enemy_id_from_scripts(scene_text: String, known: Dictionary) -> String:
	# The enemy_id named by the ENEMY_DATA constant of any script this scene
	# attaches, or "" when there is not exactly one answer.
	#
	# Reads the .gd as TEXT rather than loading it. Loading would run the class
	# through the parser during an export, and a script that does not currently
	# compile would take the whole export down with it - which is the opposite
	# of what a tool that exists to REPORT problems should do.
	var marker: String = "res://data/enemies/"
	var found: String = ""

	var search_from: int = 0
	while true:
		var at: int = scene_text.find("res://src/", search_from)
		if at == -1:
			break
		var end: int = scene_text.find(".gd", at)
		search_from = at + 10
		if end == -1:
			continue
		var script_path: String = scene_text.substr(at, end - at + 3)

		var file := FileAccess.open(script_path, FileAccess.READ)
		if file == null:
			continue
		var code: String = file.get_as_text()
		file.close()

		var const_at: int = code.find("ENEMY_DATA")
		if const_at == -1:
			continue
		var path_at: int = code.find(marker, const_at)
		if path_at == -1:
			continue
		var tres_at: int = code.find(".tres", path_at)
		if tres_at == -1:
			continue
		var candidate: String = code.substr(
			path_at + marker.length(), tres_at - path_at - marker.length())
		if not known.has(candidate):
			continue

		# TWO DIFFERENT ANSWERS IS NOT AN ANSWER. A scene attaching two scripts
		# that each name a different enemy is ambiguous, and guessing would put
		# the ceiling on the wrong one - which under-counts the other and
		# exempts it. Returning "" leaves both alone.
		if found != "" and found != candidate:
			return ""
		found = candidate

	return found


func _count_instances(world_text: String, scene_path: String) -> int:
	# How many nodes in this world are instances of that scene.
	#
	# A .tscn names each external resource once, with an id, and every node instanced
	# from it repeats that id - so the id is found once and its instance lines
	# counted. Bounded to the ext_resource's own line, because the path also
	# appears in other places and only that line carries the id.
	var at: int = world_text.find(scene_path)
	if at == -1:
		return 0
	var line_end: int = world_text.find("\n", at)
	if line_end == -1:
		line_end = world_text.length()
	var id_at: int = world_text.find("id=\"", at)
	if id_at == -1 or id_at > line_end:
		return 0
	id_at += 4
	var id_end: int = world_text.find("\"", id_at)
	if id_end == -1:
		return 0

	var needle: String = "instance=ExtResource(\"%s\")" % world_text.substr(id_at, id_end - id_at)
	var count: int = 0
	var search_from: int = 0
	while true:
		var hit: int = world_text.find(needle, search_from)
		if hit == -1:
			break
		count += 1
		search_from = hit + needle.length()
	return count


func _report_unplaced_enemies() -> void:
	# AN ENEMY NOBODY CAN MEET IS A PET NOBODY CAN GET.
	#
	# _report_reachability() above counts items shelved above every drop ceiling.
	# This is the other half of the same question, one step further back: an item
	# can be perfectly reachable in the loot table and still unobtainable because
	# the ENEMY that carries it is not placed in any scene. The pets are the case
	# that matters - each one is carried by exactly one enemy, so an unplaced
	# enemy silently removes a collectable from the game with nothing anywhere
	# reporting it.
	#
	# BY SCENE PATH, NOT BY enemy_id, and that is deliberate. Nothing connects an
	# enemy .tscn to its EnemyData as data - the scene names a script, the script
	# knows the resource - so mapping one to the other would mean a hand-written
	# table here, which is the same duplicated-decision antipattern this file
	# exists to prevent. Comparing paths needs no map and cannot drift.
	#
	# A WARNING, NEVER AN ERROR. An enemy spawned from GDScript at runtime is
	# invisible to this check: it only reads scenes. The poison slime duplicates
	# itself through a path in its own script, and a future spawner could place
	# anything. So this reports a suspicion for a human to confirm, not a verdict.
	var enemy_scenes: Array = _find_files("res://scene/enemy/", ".tscn")
	if enemy_scenes.is_empty():
		return

	# Every .tscn in the project EXCEPT the enemy scenes themselves. An enemy
	# referenced only by another enemy is still worth flagging - a boss summoning
	# a stalker is real, but so is a leftover reference in a scene nothing loads.
	var referenced: Dictionary = {}
	for scene_path in _find_files("res://scene/", ".tscn"):
		if scene_path.begins_with("res://scene/enemy/"):
			continue
		var file := FileAccess.open(scene_path, FileAccess.READ)
		if file == null:
			continue
		var text: String = file.get_as_text()
		file.close()
		for enemy_scene in enemy_scenes:
			if text.find(enemy_scene) != -1:
				referenced[enemy_scene] = true

	var unplaced: Array = []
	for enemy_scene in enemy_scenes:
		if not referenced.has(enemy_scene):
			unplaced.append(String(enemy_scene).get_file())

	if unplaced.is_empty():
		return

	unplaced.sort()
	var names := PackedStringArray()
	for scene_name in unplaced:
		names.append(String(scene_name))
	print("    %d enemy scene(s) are placed in no world scene: %s"
		% [unplaced.size(), ", ".join(names)])
	print("      Anything they alone drop - pets especially - cannot be obtained.")
	print("      Runtime spawning from GDScript is invisible here; confirm before acting.")


func _report_reachability(items: Array, enemies: Array) -> void:
	# NOT A FAILURE — A HEADCOUNT. Shelving content by putting it above every
	# enemy's ceiling is a deliberate move here (the jade rod and the large
	# potions are waiting on a boss that does not exist yet), so this cannot
	# refuse. But "finished and unreachable" and "finished and forgotten" look
	# identical in the data, and printing the number once an export is the
	# cheapest way to tell them apart.
	var ceiling: int = 0
	for enemy in enemies:
		ceiling = maxi(ceiling, int(enemy.get("max_loot_tier", 1)))

	var excluded := ["PET", "QUEST", "CURRENCY", "FISH"]
	var shelved: Array = []
	for item in items:
		if not bool(item.get("droppable", true)):
			continue
		if String(item.get("type_name", "")) in excluded:
			continue
		if int(item.get("tier", 1)) > ceiling:
			shelved.append(item["item_id"])

	if shelved.is_empty():
		return

	shelved.sort()

	# PackedStringArray explicitly: String.join() takes one, and handing it a
	# plain Array leans on an implicit conversion to do the right thing with
	# Variants. Not worth finding out mid-export.
	var sample := PackedStringArray()
	for item_id in shelved.slice(0, 8):
		sample.append(String(item_id))
	var line: String = "      " + ", ".join(sample)
	if shelved.size() > sample.size():
		line += ", ..."

	print("    %d droppable items sit above every enemy ceiling (tier %d) and cannot drop:"
		% [shelved.size(), ceiling])
	print(line)


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
			_warn("%s has an empty item_id — skipped." % path)
			continue

		# A duplicate item_id is a real defect, not a cosmetic one: the server
		# would index by id and one of the two would simply vanish from every
		# loot table with no error anywhere.
		if seen.has(item.item_id):
			_fail("duplicate item_id '%s' in %s and %s" % [item.item_id, seen[item.item_id], path])
			continue
		seen[item.item_id] = path
		_check_restores(item, path)
		_check_icon(item)

		# COPIED OUT ELEMENT BY ELEMENT rather than handed over as-is.
		# ItemData.required_classes is an Array[String] belonging to a Resource
		# that stays loaded; putting it straight in the row would export a
		# reference to the live array and hand a TYPED array to the JSON
		# writer. A plain Array of plain Strings is what the file should
		# contain and what _validate_equipment() below reads back.
		var required_classes: Array = []
		for class_id in item.required_classes:
			required_classes.append(String(class_id))

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

			# THE SKILL GATE, exported even though nothing on the server reads
			# it yet. It is the half of the requirement that cannot be a
			# character level — see itemdata.gd's comment on required_skill —
			# and the trade endpoint is where it has to be enforced, so it has
			# to reach the JSON before that endpoint can be written. Same
			# uniform row shape as the cooking fields below: exported for every
			# item, with "" meaning no requirement, so the Python side never has
			# to ask what type it is holding first.
			"required_skill": item.required_skill,
			"required_skill_level": item.required_skill_level,

			# WHAT DRINKING IT ACTUALLY DOES. Exported because the server now
			# has two reasons to know, and neither existed when these fields
			# were client-only.
			#
			# /api/character/consume destroys the item, so it ought to be able
			# to say what it authorised rather than only that something
			# happened. And _report_unexplained_heals() compares a rise in hp
			# against what regeneration plus authorised potions could account
			# for - without an amount, ANY potion inside the window explains
			# ANY rise, which is a check with a hole the width of one cheap
			# potion.
			#
			# EXPORTED FOR EVERY ITEM, with target 0 (NONE) and amount 0 for
			# things that restore nothing, so the Python side never has to ask
			# what type it is holding before reading the fields.
			#
			# The NAME sits beside the integer for the same reason type_name
			# does: ItemData.RestoreTarget is an ordered enum, and inserting a
			# value at the top would renumber every one below it while a server
			# filtering on `== 1` carried on silently doing the wrong thing.
			"restore_target": int(item.restore_target),
			"restore_target_name": _restore_target_name(int(item.restore_target)),
			"restore_amount": item.restore_amount,

			# Whether an enemy may roll it at all, independent of its tier.
			# pick_weighted_item_id() has to skip a false here or a cooked fish
			# drops off a slime — see the field's own comment in itemdata.gd.
			"droppable": item.droppable,

			# WHAT WEARING IT MEANS. The save endpoint stores a character's
			# equipment as {slot_name: item_id}, and until these shipped it
			# could check only that the id named SOME item — so
			# {"helm": "embersword"} was a legal save and the player wore a
			# sword on their head with the server's blessing.
			#
			# required_classes is here for the same reason and is the sharper
			# one: it is the only gate stopping a warrior wearing a mage's robe
			# for its armour, and a gate the client alone enforces is a
			# suggestion.
			#
			# EXPORTED FOR EVERY ITEM — slot NONE, no classes, zero damage,
			# zero armour on a health potion — so the server reads the fields
			# without first asking what type it is holding. Same uniform row
			# shape as the cooking and restore blocks above.
			"equip_slot": int(item.equip_slot),
			"equip_slot_name": _equip_slot_name(int(item.equip_slot)),
			"required_classes": required_classes,

			# The numbers combat reads. `damage` is the MIDDLE of a band rather
			# than a fixed hit - damage_spread is how far either side of it a
			# roll can land, so an iron sword at 20 with a spread of 0.25 hits
			# for somewhere in 15-25.
			#
			# THE SPREAD IS EXPORTED EVEN THOUGH NOTHING ON THE SERVER ROLLS
			# ANYTHING. It is the only thing that can answer "could that hit
			# have come from that weapon", and the day the server starts
			# checking damage - or a second player watches the numbers pop off
			# an enemy - the band is what makes the question answerable.
			#
			# Authored per class, not per tier alone: a scepter fires ten times
			# a second and a sword swings once, so equal numbers would not be
			# equal weapons. See mage.gd and healer.gd on why the ladders differ.
			"damage": item.damage,
			"damage_spread": item.damage_spread,
			"armor_value": item.armor_value,

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


func _check_icon(item: ItemData) -> void:
	# AN ITEM WITH NO ICON IS AN EMPTY-LOOKING CELL.
	#
	# ItemData.icon is a Texture2D, and a .tres pointing at art that is not
	# there loads with it null rather than failing - so the item exists, drops,
	# stacks and is worth gold, and renders as nothing. In a grid of slots that
	# are ALSO empty, the difference between "no item" and "an item with no
	# picture" is invisible.
	#
	# CHECKED HERE RATHER THAN OVER THE EXPORTED ROWS because the icon is not in
	# them - the server has no use for a texture. This is the only pass with the
	# resource open, the same reason _check_restores() lives beside it.
	#
	# A WARNING, NOT AN ERROR. Art arrives in batches and a placeholder-less item
	# is a normal state mid-pipeline; refusing to export would block the server
	# on a missing PNG it does not read.
	if item.icon == null:
		_iconless.append(item.item_id)


func _check_restores(item: ItemData, path: String) -> void:
	# A POTION THAT RESTORES NOTHING IS THE QUIETEST BUG IN THE CATALOGUE. The
	# use-handler routes by restore_target and applies restore_amount; if either
	# half is missing it takes the item, plays the sound, restores zero and says
	# nothing. The player reads that as the potion "not working" and there is no
	# error anywhere to disagree with them.
	#
	# The two halves fail differently, so they are reported differently:

	# AMOUNT WITH NO TARGET is always a mistake. There is no reading of
	# "restores 140 of nothing" that anyone intended.
	if item.restore_amount > 0 and item.restore_target == ItemData.RestoreTarget.NONE:
		_fail("'%s' restores %d but has restore_target = NONE — the restore goes nowhere. (%s)" % [item.item_id, item.restore_amount, path])
		return

	# TARGET WITH NO AMOUNT is the same mistake wearing the other shoe.
	if item.restore_target != ItemData.RestoreTarget.NONE and item.restore_amount <= 0:
		_fail("'%s' has a restore_target set but restore_amount = %d — using it does nothing. (%s)" % [item.item_id, item.restore_amount, path])
		return

	# NEITHER HALF SET, on a CONSUMABLE, is only PROBABLY wrong. RestoreTarget's
	# own comment reserves NONE for "food that does something else", and nothing
	# does something else yet — so this warns and lets the export through rather
	# than blocking the first item that uses the door the enum deliberately left
	# open.
	if item.type == ItemData.Type.CONSUMABLE and item.restore_target == ItemData.RestoreTarget.NONE:
		_warn("CONSUMABLE '%s' restores nothing — using it will consume it with no effect." % item.item_id)


func _type_name(type_index: int) -> String:
	if type_index < 0 or type_index >= TYPE_NAMES.size():
		# An enum value with no name means ItemData.Type gained an entry that
		# TYPE_NAMES above did not. Say so loudly — a silent "UNKNOWN" would
		# end up in a loot filter on the server.
		_fail("ItemData.Type value %d has no name in TYPE_NAMES — update this script." % type_index)
		return "UNKNOWN_%d" % type_index
	return TYPE_NAMES[type_index]


func _restore_target_name(target_index: int) -> String:
	if target_index < 0 or target_index >= RESTORE_TARGET_NAMES.size():
		# Same reasoning as _type_name() above. A silent "UNKNOWN" here would
		# reach the server's healing reconciler, match no stat, and turn every
		# potion of that kind into an unexplained heal in the log.
		_fail("ItemData.RestoreTarget value %d has no name in RESTORE_TARGET_NAMES — update this script." % target_index)
		return "UNKNOWN_%d" % target_index
	return RESTORE_TARGET_NAMES[target_index]


func _equip_slot_name(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= EQUIP_SLOT_NAMES.size():
		# Same reasoning as the two above, with a worse landing. The server
		# validates a save's equipment against this vocabulary, so an
		# "UNKNOWN_9" would name a slot no client can send and every attempt to
		# wear the new piece would come back 400 with nothing to say why.
		_fail("ItemData.EquipSlot value %d has no name in EQUIP_SLOT_NAMES — update this script." % slot_index)
		return "UNKNOWN_%d" % slot_index
	return EQUIP_SLOT_NAMES[slot_index]


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
			_warn("%s has an empty enemy_id — skipped." % path)
			continue

		# A duplicate id is a hard error for the same reason it is with items:
		# the server indexes by id, so one of the two would simply vanish from
		# the roster with nothing anywhere to say it had.
		if seen.has(enemy.enemy_id):
			_fail("duplicate enemy_id '%s' in %s and %s" % [enemy.enemy_id, seen[enemy.enemy_id], path])
			continue
		seen[enemy.enemy_id] = path

		out.append({
			"enemy_id":          enemy.enemy_id,
			"display_name":      enemy.display_name,
			"resource":          path,
			"grants_rewards":    enemy.grants_rewards,
			# The server does not use this YET. It is here because elemental
			# damage is a design commitment rather than a maybe, and the moment
			# the server resolves a resistance it needs to know what hit the
			# player — at which point a field that has been in the contract all
			# along costs nothing, and one that has not means every deployed
			# client is sending kills the server cannot price.
			#
			# body_tint and projectile_damage are deliberately NOT here. A
			# colour is how the player recognises an element and a projectile's
			# damage is client simulation; neither helps the server decide what
			# a kill is worth, which is the line this file draws.
			"element":           enemy.element,
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


func _export_shops(items: Array) -> Array:
	# Reads data/shops/*.tres. Structurally the same as _export_items() above.
	#
	# WHY SHOPS ARE EXPORTED AT ALL. The buy happens on the server, so the
	# server has to know what each vendor stocks — otherwise the client would
	# send "I bought this" and be believed, which is the one thing
	# ShopData.gd's header exists to prevent. The catalogue is authored in
	# Godot because that is where the items are; it crosses to Python the same
	# way everything else does.
	#
	# NOT FATAL WHEN EMPTY, unlike items and enemies. A project with no shops
	# yet is a valid project, and refusing to write the whole catalogue over a
	# missing vendor would be a worse failure than the one it prevents.
	var out: Array = []
	var seen: Dictionary = {}

	# Built once rather than per stock row: every id is checked against it, and
	# a linear scan of the catalogue per row would be quadratic on a big shop.
	var known: Dictionary = {}
	for row in items:
		known[String(row.get("item_id", ""))] = true

	for path in _find_files(SHOPS_PATH, ".tres"):
		var res: Resource = ResourceLoader.load(path)
		if res == null or not (res is ShopData):
			continue

		var shop: ShopData = res

		if shop.shop_id == "":
			_warn("%s has an empty shop_id — skipped." % path)
			continue

		if seen.has(shop.shop_id):
			_fail("duplicate shop_id '%s' in %s and %s" % [shop.shop_id, seen[shop.shop_id], path])
			continue
		seen[shop.shop_id] = path

		# A stock id naming no item is a row the player can click and not
		# receive. Hard error for the same reason a bad gold_small_id is: the
		# failure is silent and only shows up as a vendor that takes money and
		# hands over nothing.
		var stock: Array = []
		for entry in shop.stock:
			var item_id: String = String(entry)
			if item_id == "":
				continue
			if not known.has(item_id):
				_fail("shop '%s' stocks '%s', which names no item." % [shop.shop_id, item_id])
				continue
			if stock.has(item_id):
				_warn("shop '%s' lists '%s' twice — kept once." % [shop.shop_id, item_id])
				continue
			stock.append(item_id)

		if stock.is_empty():
			_warn("shop '%s' stocks nothing — it will open empty." % shop.shop_id)

		out.append({
			"shop_id":          shop.shop_id,
			"display_name":     shop.display_name,
			"stock":            stock,
			"price_multiplier": float(shop.price_multiplier),
			"restock_seconds":  float(shop.restock_seconds),
		})

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
			_warn("%s has an empty class_id — skipped." % path)
			continue
		if seen.has(cls.class_id):
			_fail("duplicate class_id '%s' in %s and %s" % [cls.class_id, seen[cls.class_id], path])
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

	# playerstats.gd, for the regen rates. Read from the script that DEFINES
	# them rather than from the player scene, because they are constants there
	# now precisely so this line can exist - see the note above
	# PlayerStats.REGEN_PERCENT_PER_SECOND.
	var stat_consts: Dictionary = (load("res://src/characters/playerstats.gd") as GDScript).get_script_constant_map()

	return {
		"large_gold_threshold": int(enemy_consts.get("LARGE_GOLD_THRESHOLD", 100)),
		"gold_small_id":        String(enemy_consts.get("GOLD_SMALL_ID", "smallamountofgold")),
		"gold_large_id":        String(enemy_consts.get("GOLD_LARGE_ID", "largeamountofgold")),
		# THE COIN LADDER, so the server makes change out of the same list the
		# game does. Exported as ids only - each coin's value travels with the
		# item record, where it belongs.
		"gold_denomination_ids": enemy_consts.get("GOLD_DENOMINATION_IDS", []),
		# THE JACKPOT DICE. Exported so the server rolls the same odds the
		# game declares - two tables that disagree is a payout nobody can
		# reason about.
		"gold_jackpot_dice":  int(enemy_consts.get("GOLD_JACKPOT_DICE", 0)),
		"gold_jackpot_min_tier": int(enemy_consts.get("GOLD_JACKPOT_MIN_TIER", 0)),
		"gold_jackpot_faces": int(enemy_consts.get("GOLD_JACKPOT_FACES", 6)),
		"gold_jackpot_multipliers": enemy_consts.get("GOLD_JACKPOT_MULTIPLIERS", []),

		# THE GOLD CURVE. Read off baseenemy.gd for the same reason the three
		# lines above are: the server rolls the gold, the constant lives with the
		# enemy, and a second copy of 2.6 in Python is a number that drifts.
		"gold_tier_ratio":      float(enemy_consts.get("GOLD_TIER_RATIO", 2.6)),
		"gold_base_unit":       float(enemy_consts.get("GOLD_BASE_UNIT", 1.0)),
		"gold_spread":          int(enemy_consts.get("GOLD_SPREAD", 25)),
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
		# WHAT ONE LUSION IS WORTH IN GOLD. Only needed where two currencies
		# are added into one number - the score - and stated once so the day
		# it is tuned it moves everywhere at once.
		"lusion_gold_value":    int(game_consts.get("LUSION_GOLD_VALUE", 1000)),

		# The gold alternative to that lusion price. A share rather than a
		# figure, so the server computes it against a balance it owns rather
		# than being told what the revive should cost.
		"revive_gold_rate":     float(game_consts.get("REVIVE_GOLD_RATE", 0.80)),
		"revive_gold_minimum":  int(game_consts.get("REVIVE_GOLD_MINIMUM", 100)),

		# HOW FAST A CHARACTER RECOVERS ON ITS OWN, which the server needs in
		# order to tell an honest rise in health from an invented one. Without
		# these it was measuring against two numbers retyped into app.py, and
		# a copied constant in this project has form: the XP formula lived in
		# two places, drifted, and the sanitiser began rewriting honest saves.
		#
		# The idle threshold goes across even though the server cannot act on
		# it - it has no idea whether you stood still, so it allows regen for
		# the whole window. It is here for the day presence exists, and so the
		# number is not discovered twice.
		"regen_percent_per_second": float(stat_consts.get("REGEN_PERCENT_PER_SECOND", 0.0167)),
		"regen_minimum_per_second": float(stat_consts.get("REGEN_MINIMUM_PER_SECOND", 1.0)),
		"regen_idle_threshold":     float(stat_consts.get("REGEN_IDLE_THRESHOLD", 1.0)),

		# WHAT ARMOUR TAKES OFF, as the armour value at which incoming damage
		# is halved. Nothing on the server reads it: damage to the PLAYER is
		# applied client-side, which is the one direction the server has never
		# needed to police, because a client that lies about how much it was
		# hurt is only cheating itself out of a death.
		#
		# Exported anyway, for the same reason regen_idle_threshold is. The day
		# a second player can see your health bar, this is the number that says
		# whether what they are seeing is possible, and it should not have to
		# be discovered twice.
		"armour_half_point":    float(stat_consts.get("ARMOUR_HALF_POINT", 200.0)),
		"cook_burn_max":        float(game_consts.get("COOK_BURN_MAX", 0.40)),
		"fishing_tier_per_level": int(game_consts.get("FISHING_TIER_PER_LEVEL", 20)),
		"skill_xp_base":        int(game_consts.get("SKILL_XP_BASE", 100)),
		"skill_xp_growth":      game_consts.get("SKILL_XP_GROWTH", {}),

		# THE KINGDOM TAX. The server is the only thing that may charge it -
		# a client that computed its own tax would be a client that charged
		# itself nothing - but the RATE is a balance decision and belongs with
		# the rest of them, here, where somebody tuning the economy will look.
		# The trade panel shows the player the same number the server takes.
		"kingdom_tax_rate":     float(game_consts.get("KINGDOM_TAX_RATE", 0.05)),
		"kingdom_tax_minimum":  int(game_consts.get("KINGDOM_TAX_MINIMUM", 1)),

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
		_fail("cannot open %s" % root)
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
