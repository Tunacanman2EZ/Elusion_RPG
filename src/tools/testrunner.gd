# testrunner.gd — the game side's test suite. Run it headless:
#
#     godot --headless --path . res://scene/tests/tests.tscn
#
# Exits 0 if everything passes, 1 if anything fails, so it can gate a commit the
# same way test_api.py does.
#
# WHY THIS EXISTS
# ---------------
# Every one of the 367 tests in this project is on the Flask side. The Godot half
# has only ever been verified by booting it and reading the log, which is how an
# owner panel bound to a key that closes the game, a dead revive branch that
# could never be reached, and a README describing a deleted file all survived.
# None of those were carelessness. They were the absence of anything that fails.
#
# WHAT BELONGS IN HERE
# --------------------
# Logic that can be checked without playing the game: curves, arithmetic, save
# round trips, and above all THE NUMBERS THAT MUST AGREE WITH THE SERVER. Those
# are the ones where drift is silent and expensive — the XP curve once lived in
# two places, disagreed, and rewrote every save on load for a day before anyone
# worked out why.
#
# What does NOT belong: anything needing a player in a world, a physics frame, or
# a rendered scene. That is what booting the game is for.
extends Node


# WHERE THE RESULTS GO
# --------------------
# Every line is printed AND kept, and the whole transcript is written to
# res://test_results.txt at the end.
#
# The file is not a convenience. Running this from the Godot editor with F6
# should put the prints in the Output panel, and running it from a terminal
# should put them on stdout - and on Windows both have failed, for unrelated
# reasons, on the machine this was written for. A test suite whose results can
# vanish depending on how it was launched is not a test suite. The file is
# always there afterwards, and it is the same text either way.
const RESULTS_PATH := "res://test_results.txt"

var passed: int = 0
var failed: int = 0
var failures: PackedStringArray = []
var _log: PackedStringArray = []


func _ready() -> void:
	# Wait one frame before doing anything. Calling get_tree().quit() from inside
	# _ready(), while the tree and the autoloads are still coming up, is a bad
	# idea on its own terms: the suite would be judging a half-built world.
	#
	# THIS COMMENT USED TO CLAIM THE AWAIT ALSO PREVENTED "ObjectDB instances
	# leaked at exit", and that it was harmless when it appeared. Both halves
	# were wrong, and the first run this file ever completed printed the warning
	# anyway. Running it with --verbose named the culprit in one line: a leaked
	# GDScriptFunctionState with orphan StringNames get_json, request_completed
	# and completed - api.gd's unawaited boot probe, still waiting on a three
	# second HTTP timeout when quit() arrived. Fixed there, with the reasoning.
	#
	# WORTH KEEPING AS A LESSON. A comment asserting that a warning is harmless
	# is the most expensive kind of comment there is: it does not just fail to
	# help, it actively tells the next person not to look. A comment cannot fail,
	# so this one went unexamined from the day it was written until the day the
	# file first ran.
	await get_tree().process_frame
	_say("")
	_run_all()
	_report()


func _run_all() -> void:
	_test_curve_agreement()
	_test_skill_curves()
	_test_shared_constants()
	_test_class_curves()
	_test_enemy_constants()
	_test_player_stats()
	_test_facing()
	_test_formation()
	_test_pet_controller()
	_test_itemstack()
	_test_ranks()
	_test_collision_contract()


# =============================================================================
# HARNESS
# =============================================================================

func _say(line: String) -> void:
	print(line)
	_log.append(line)


func check(label: String, condition: bool, detail: Variant = "") -> void:
	if condition:
		passed += 1
		_say("  pass  %s" % label)
	else:
		failed += 1
		failures.append(label)
		_say("  FAIL  %s   %s" % [label, str(detail)])


func section(title: String) -> void:
	# RE-ARMED EVERY SECTION. quietly() below turns engine messages off and on
	# around a single call, and if that call ever aborts between the two the flag
	# stays off and the rest of the run goes silent - including real errors. This
	# line means the damage can never outlive one section.
	Engine.print_error_messages = true
	_say("")
	_say(title)
	_say("-".repeat(title.length()))


func quietly(fn: Callable) -> Variant:
	# RUN ONE CALL WITH THE ENGINE'S MESSAGES OFF, and hand back what it returned.
	#
	# WHY THIS EXISTS. Several checks in this suite deliberately do the wrong
	# thing and assert that the code REFUSES: an unknown item_id, a consumable
	# asked to be a pet, a non-pet sitting in the pets group. Refusing is the
	# behaviour under test, and push_warning() is how each refusal announces
	# itself - so a fully passing run printed five warnings and fifteen lines of
	# backtrace, and the suite had to apologise for them in its own output with
	# "...expected warnings follow".
	#
	# That is the same disease as the leaked-instance warning that came out of
	# api.gd's boot probe: NOISE ON A GREEN RUN. It teaches you to skim the
	# console, and skimming the console is how a 46 hour stale catalogue with
	# four disarmed security controls survived.
	#
	# Engine.print_error_messages is the only lever GDScript has here, and it is
	# a BIG HAMMER - while it is off, genuine errors vanish too. So it is off for
	# exactly one call and on again on the next line, never around a block, and
	# section() re-arms it regardless.
	#
	# THE WARNINGS THEMSELVES ARE NOT THE PROBLEM AND ARE NOT BEING SUPPRESSED IN
	# THE GAME. A player who somehow lands on a missing item_id should absolutely
	# see it in the console. This only silences the calls where this file is the
	# one asking for the impossible thing.
	Engine.print_error_messages = false
	var out: Variant = fn.call()
	Engine.print_error_messages = true
	return out


func _environment() -> void:
	# Written into the results file because the first three attempts to run this
	# suite all failed at "which binary is Godot and where does its output go",
	# and none of those questions had an answer visible from inside the project.
	_say("Godot %s" % Engine.get_version_info().get("string", "unknown"))
	_say("executable: %s" % OS.get_executable_path())
	_say("project:    %s" % ProjectSettings.globalize_path("res://"))
	_say("results:    %s" % ProjectSettings.globalize_path(RESULTS_PATH))


func _report() -> void:
	_say("")
	_say("=".repeat(60))
	_say("  %d passed, %d failed" % [passed, failed])
	if failed > 0:
		_say("")
		_say("  failing checks:")
		# `label`, not `name` - Node.name exists and shadowing it warns at parse.
		for label in failures:
			_say("    - " + label)
	_say("=".repeat(60))
	_environment()
	_say("")

	_write_results()
	get_tree().quit(1 if failed > 0 else 0)


func _write_results() -> void:
	# Before quit(), not after. quit() is deferred to the end of the frame so
	# either order happens to work, but "write the file, then ask to exit" is
	# the order that stays correct if that ever changes.
	var file := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if file == null:
		# res:// is writable when running from the editor and read-only inside an
		# exported build. This suite is a development tool, so that is fine - but
		# say so rather than silently producing no file.
		print("  (could not write %s: %s)"
			% [RESULTS_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string("\n".join(_log) + "\n")
	file.close()


func _load_gamedata() -> Dictionary:
	# The exported contract both sides read. If this is missing or stale the
	# server is running on different numbers than the game, which is the single
	# most expensive kind of drift in this project.
	var file := FileAccess.open("res://data/gamedata.json", FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


# =============================================================================
# THE CURVE THE SERVER ALSO USES
# =============================================================================

func _test_curve_agreement() -> void:
	section("XP CURVE — GAME vs EXPORTED CONTRACT")

	var data := _load_gamedata()
	check("data/gamedata.json loads", not data.is_empty(),
		"missing or unparseable — re-run src/tools/exportgamedata.gd")
	if data.is_empty():
		return

	var constants: Dictionary = data.get("constants", {})

	check("the exported xp_base matches GameConstants",
		is_equal_approx(float(constants.get("xp_base", -1.0)), GameConstants.XP_BASE),
		"exported %s, game %s" % [constants.get("xp_base"), GameConstants.XP_BASE])

	check("the exported xp_growth matches GameConstants",
		is_equal_approx(float(constants.get("xp_growth", -1.0)), GameConstants.XP_GROWTH),
		"exported %s, game %s" % [constants.get("xp_growth"), GameConstants.XP_GROWTH])

	# THE ACTUAL CURVE, not just its inputs. The server recomputes from these two
	# numbers; if its formula ever differs from ours, matching constants would
	# hide it. Same arithmetic, same answers, at the levels people play.
	var base: float = float(constants.get("xp_base", GameConstants.XP_BASE))
	var growth: float = float(constants.get("xp_growth", GameConstants.XP_GROWTH))
	for level in [1, 2, 5, 10, 25, 50, 99]:
		var expected: int = int(base * pow(growth, max(level - 1, 0)))
		check("level %d needs the same XP on both sides" % level,
			GameConstants.xp_needed_for_level(level) == expected,
			"game %d, contract %d" % [GameConstants.xp_needed_for_level(level), expected])

	# Level 1 is the boundary the -1 in the formula exists for, and a corrupted
	# level of 0 or below must not produce a fractional power.
	check("level 1 costs exactly the base",
		GameConstants.xp_needed_for_level(1) == int(GameConstants.XP_BASE),
		GameConstants.xp_needed_for_level(1))
	check("level 0 does not go below the base",
		GameConstants.xp_needed_for_level(0) == int(GameConstants.XP_BASE),
		GameConstants.xp_needed_for_level(0))
	check("a negative level does not either",
		GameConstants.xp_needed_for_level(-5) == int(GameConstants.XP_BASE),
		GameConstants.xp_needed_for_level(-5))

	# The overflow this curve replaced. The old formula doubled, which leaves
	# int64 somewhere around level 58 — so the guard is that a high level stays
	# a sane positive number rather than a wrapped one.
	check("level 99 stays inside int64",
		GameConstants.xp_needed_for_level(99) > 0
		and GameConstants.xp_needed_for_level(99) < 9223372036854775807,
		GameConstants.xp_needed_for_level(99))


func _test_skill_curves() -> void:
	section("SKILL XP CURVES — GAME vs EXPORTED CONTRACT")

	# WHY THIS EXISTS. The character curve above already has this test because
	# that formula once lived in two places, drifted, and the sanitizer rewrote
	# honest saves. The SIX SKILL curves had grown the same problem quietly:
	# GameConstants.SKILL_XP_GROWTH is the copy exported to the server, and
	# player.gd's gain_*_xp() functions each passed their own literal factor.
	#
	# It matters more now than it did. attack, fishing and cooking are granted
	# BY THE SERVER, so the client no longer decides those levels - it only
	# draws the bar. If the client's threshold disagreed with the server's, the
	# bar would fill to a level the server never reaches, or jump past one it
	# already stored, and nothing would report it.

	var data := _load_gamedata()
	if data.is_empty():
		check("gamedata.json needed for the skill-curve comparison", false, "see above")
		return

	var constants: Dictionary = data.get("constants", {})
	var exported: Dictionary = constants.get("skill_xp_growth", {})

	check("the contract carries a skill_xp_growth table",
		not exported.is_empty(), "re-run src/tools/exportgamedata.gd")

	check("the exported skill_xp_base matches GameConstants",
		int(constants.get("skill_xp_base", -1)) == GameConstants.SKILL_XP_BASE,
		"contract %s, game %d" % [constants.get("skill_xp_base"), GameConstants.SKILL_XP_BASE])

	# EVERY skill, both directions. A one-way loop would pass while the contract
	# carried a seventh skill the game has never heard of.
	for skill_id in GameConstants.SKILL_XP_GROWTH:
		check("the contract knows about '%s'" % skill_id, exported.has(skill_id), exported.keys())
		if exported.has(skill_id):
			check("'%s' grows at the same rate on both sides" % skill_id,
				is_equal_approx(float(exported[skill_id]),
					float(GameConstants.SKILL_XP_GROWTH[skill_id])),
				"contract %s, game %s" % [exported[skill_id], GameConstants.SKILL_XP_GROWTH[skill_id]])

	for skill_id in exported:
		check("the game knows about the contract's '%s'" % skill_id,
			GameConstants.SKILL_XP_GROWTH.has(skill_id), GameConstants.SKILL_XP_GROWTH.keys())

	# THE ACTUAL THRESHOLDS, not just the inputs - same reasoning as the
	# character curve above. The server recomputes from base and factor; if its
	# arithmetic ever differs from PlayerStats', matching constants hide it.
	for skill_id in GameConstants.SKILL_XP_GROWTH:
		var factor: float = float(GameConstants.SKILL_XP_GROWTH[skill_id])
		for level in [1, 2, 10, 50]:
			var expected: int = int(GameConstants.SKILL_XP_BASE * pow(factor, max(level - 1, 0)))
			var actual: int = PlayerStats.xp_needed_for_skill(
				level, GameConstants.SKILL_XP_BASE, factor)
			check("%s level %d costs the same on both sides" % [skill_id, level],
				actual == expected, "game %d, contract %d" % [actual, expected])

	# A FALLBACK BOTH SIDES SHARE. gamedata.py answers 1.18 for a skill the
	# table does not list; PlayerStats.SKILL_XP_FACTOR is the client's. An
	# unlisted skill must be paced identically, not two different ways.
	check("the unlisted-skill fallback matches the server's 1.18",
		is_equal_approx(PlayerStats.SKILL_XP_FACTOR, 1.18),
		PlayerStats.SKILL_XP_FACTOR)

	# The two gathering numbers the server reads out of the same contract.
	check("cook_burn_max matches GameConstants",
		is_equal_approx(float(constants.get("cook_burn_max", -1.0)), GameConstants.COOK_BURN_MAX),
		"contract %s, game %s" % [constants.get("cook_burn_max"), GameConstants.COOK_BURN_MAX])
	check("cook_burn_max is a probability",
		GameConstants.COOK_BURN_MAX >= 0.0 and GameConstants.COOK_BURN_MAX <= 1.0,
		GameConstants.COOK_BURN_MAX)
	check("fishing_tier_per_level matches GameConstants",
		int(constants.get("fishing_tier_per_level", -1)) == GameConstants.FISHING_TIER_PER_LEVEL,
		"contract %s, game %d" % [constants.get("fishing_tier_per_level"),
			GameConstants.FISHING_TIER_PER_LEVEL])


func _test_shared_constants() -> void:
	section("SHARED CONSTANTS — GameConstants vs EXPORTED CONTRACT")

	var data := _load_gamedata()
	if data.is_empty():
		check("gamedata.json needed for the constants comparison", false, "see above")
		return

	var constants: Dictionary = data.get("constants", {})

	# Both of these are quoted at the player — the game-over screen prices a
	# revive, and a duplicate pet pays out. If the exporter has not been re-run
	# since one was tuned, the server's idea of the price and the number on the
	# button disagree, and the player is the one who finds out.
	check("revive_cost matches",
		int(constants.get("revive_cost", -1)) == GameConstants.REVIVE_COST,
		"contract %s, game %d" % [constants.get("revive_cost"), GameConstants.REVIVE_COST])

	check("dupe_pet_lusions matches",
		int(constants.get("dupe_pet_lusions", -1)) == GameConstants.DUPE_PET_LUSIONS,
		"contract %s, game %d" % [constants.get("dupe_pet_lusions"), GameConstants.DUPE_PET_LUSIONS])

	# Deliberately equal — a dupe pet is exactly one free revive. The two
	# constants above can each match the contract while that relationship has
	# quietly been broken, so it gets its own check.
	check("a dupe pet is still worth exactly one revive",
		GameConstants.DUPE_PET_LUSIONS == GameConstants.REVIVE_COST,
		"%d vs %d" % [GameConstants.DUPE_PET_LUSIONS, GameConstants.REVIVE_COST])


func _test_class_curves() -> void:
	section("CLASS STAT CURVES — .tres vs EXPORTED CONTRACT")

	var data := _load_gamedata()
	if data.is_empty():
		check("gamedata.json needed for the class comparison", false, "see above")
		return

	var exported: Dictionary = {}
	for entry in data.get("classes", []):
		if entry is Dictionary:
			exported[str(entry.get("class_id", ""))] = entry

	check("the contract carries classes", not exported.is_empty(), data.get("classes"))

	var dir := DirAccess.open("res://data/classes")
	if dir == null:
		check("res://data/classes can be opened", false, "folder missing")
		return

	var found: int = 0
	for filename in dir.get_files():
		# Godot renames .tres to .tres.remap in an exported build. Both are
		# loadable by the un-suffixed path.
		if not filename.ends_with(".tres") and not filename.ends_with(".tres.remap"):
			continue
		var path := "res://data/classes/" + filename.trim_suffix(".remap")
		var res: Resource = load(path)
		if res == null or not (res is ClassData):
			check("%s loads as ClassData" % filename, false, path)
			continue

		found += 1
		var cls: ClassData = res
		var row: Dictionary = exported.get(cls.class_id, {})

		check("%s is in the exported contract" % cls.class_id, not row.is_empty(),
			"re-run src/tools/exportgamedata.gd")
		if row.is_empty():
			continue

		# THE SERVER COMPUTES max_hp FROM THESE. If a .tres is edited and the
		# exporter is not re-run, the server hands out maxima from the old curve
		# and then disagrees with the client about how much health you have.
		#
		# cls.get(field) is Object.get() — ONE argument, no default. Passing a
		# second is a parse error, not a fallback.
		for field in ["hp_base", "hp_per_lvl", "mana_base", "mana_per_lvl",
					  "stam_base", "stam_per_lvl"]:
			check("%s.%s matches" % [cls.class_id, field],
				int(row.get(field, -1)) == int(cls.get(field)),
				"contract %s, resource %s" % [row.get(field), cls.get(field)])

	check("every class resource was checked", found >= 4, "found %d" % found)


# =============================================================================
# ENEMY DROP CONSTANTS — BaseEnemy vs EXPORTED CONTRACT
# =============================================================================
# THE SERVER ROLLS THE LOOT. These constants are authored in baseenemy.gd,
# exported into data/gamedata.json by src/tools/exportgamedata.gd, and read by
# Flask when it decides what a kill pays out.
#
# So a number edited here without re-running the exporter does not produce a
# disagreement anyone can see - it produces a server quietly rolling yesterday's
# drop rates while the code says otherwise. Same failure as the XP curve, on
# numbers nobody can eyeball because they are 1-in-1296 events.

func _test_enemy_constants() -> void:
	section("ENEMY DROP RATES — BaseEnemy vs EXPORTED CONTRACT")

	var data := _load_gamedata()
	if data.is_empty():
		check("gamedata.json needed for the enemy comparison", false, "see above")
		return

	var constants: Dictionary = data.get("constants", {})

	check("large_gold_threshold matches",
		int(constants.get("large_gold_threshold", -1)) == BaseEnemy.LARGE_GOLD_THRESHOLD,
		"contract %s, game %d" % [constants.get("large_gold_threshold"),
			BaseEnemy.LARGE_GOLD_THRESHOLD])
	check("gold_small_id matches",
		str(constants.get("gold_small_id", "")) == BaseEnemy.GOLD_SMALL_ID,
		"contract %s, game %s" % [constants.get("gold_small_id"), BaseEnemy.GOLD_SMALL_ID])
	check("gold_large_id matches",
		str(constants.get("gold_large_id", "")) == BaseEnemy.GOLD_LARGE_ID,
		"contract %s, game %s" % [constants.get("gold_large_id"), BaseEnemy.GOLD_LARGE_ID])

	# Both gold ids have to name items that exist, or a kill pays out nothing.
	check("the small gold item exists", ItemRegistry.has_item(BaseEnemy.GOLD_SMALL_ID),
		BaseEnemy.GOLD_SMALL_ID)
	check("the large gold item exists", ItemRegistry.has_item(BaseEnemy.GOLD_LARGE_ID),
		BaseEnemy.GOLD_LARGE_ID)

	check("pet_odds_fallback matches",
		int(constants.get("pet_odds_fallback", -1)) == BaseEnemy.PET_ODDS_FALLBACK,
		"contract %s, game %d" % [constants.get("pet_odds_fallback"),
			BaseEnemy.PET_ODDS_FALLBACK])

	# JSON HAS NO INTEGER KEYS EITHER. The tier numbers come back as the strings
	# "1".."4", so this compares int(key) rather than key - the same coercion
	# every number crossing this boundary needs.
	var exported_odds: Dictionary = constants.get("pet_odds_by_tier", {})
	check("the contract carries pet odds per tier", not exported_odds.is_empty(),
		exported_odds)

	for tier in BaseEnemy.PET_ODDS_BY_TIER:
		var mine: int = int(BaseEnemy.PET_ODDS_BY_TIER[tier])
		var theirs: int = int(exported_odds.get(str(tier), -1))
		check("tier %d drops a pet at the same rate on both sides" % tier,
			mine == theirs, "game 1-in-%d, contract 1-in-%s" % [mine, theirs])

	check("no tier was exported that the game does not define",
		exported_odds.size() == BaseEnemy.PET_ODDS_BY_TIER.size(),
		"contract %d tiers, game %d" % [exported_odds.size(),
			BaseEnemy.PET_ODDS_BY_TIER.size()])

	# A rarer tier should never be more generous than a commoner one. This is
	# the check that catches a tuning edit typed into the wrong line - the
	# numbers are "1 in N", so they must DESCEND as the tier climbs.
	var previous: int = 1 << 30
	for tier in [1, 2, 3, 4]:
		if not BaseEnemy.PET_ODDS_BY_TIER.has(tier):
			continue
		var odds: int = int(BaseEnemy.PET_ODDS_BY_TIER[tier])
		check("tier %d is not rarer than the tier below it" % tier, odds < previous,
			"tier %d is 1-in-%d, previous was 1-in-%d" % [tier, odds, previous])
		previous = odds

	# Tier 3 is 1 in 216 on purpose: the original roll was 3d6 needing all
	# three sixes. Every other tier was tuned around that anchor, so if this
	# one moves, the others were tuned against something that no longer exists.
	check("tier 3 is still the original triple-six, 1 in 216",
		int(BaseEnemy.PET_ODDS_BY_TIER.get(3, -1)) == 216,
		BaseEnemy.PET_ODDS_BY_TIER.get(3))


# =============================================================================
# FACING — the four-direction rule, formerly written out ten times
# =============================================================================

func _test_facing() -> void:
	section("FACING")

	check("a clear right", Facing.from_vec(Vector2(10, 1)) == Facing.RIGHT)
	check("a clear left", Facing.from_vec(Vector2(-10, 1)) == Facing.LEFT)
	check("a clear down", Facing.from_vec(Vector2(1, 10)) == Facing.DOWN)
	check("a clear up", Facing.from_vec(Vector2(1, -10)) == Facing.UP)

	# THE BOUNDARY. `abs(x) > abs(y)` is false when they are equal, so a perfect
	# diagonal resolves vertically. Not obviously right or wrong - but it is a
	# decision, and an undocumented decision is one somebody "fixes" later.
	check("a perfect diagonal goes vertical, not horizontal",
		Facing.from_vec(Vector2(1, 1)) == Facing.DOWN, Facing.from_vec(Vector2(1, 1)))
	check("and the same upward", Facing.from_vec(Vector2(-1, -1)) == Facing.UP)

	# THE DISAGREEMENT THIS CLASS EXISTS TO SETTLE. The enemy copies returned ""
	# here; the player and class copies returned "up". Both are now reachable,
	# by name, from one place.
	check("a zero vector has no direction", Facing.from_vec(Vector2.ZERO) == Facing.NONE)
	check("...unless the caller needs one",
		Facing.from_vec_total(Vector2.ZERO) == Facing.UP,
		Facing.from_vec_total(Vector2.ZERO))
	check("and the caller can pick a different one",
		Facing.from_vec_total(Vector2.ZERO, Facing.DOWN) == Facing.DOWN)
	check("a total answer still prefers the real direction when there is one",
		Facing.from_vec_total(Vector2(10, 1)) == Facing.RIGHT)

	# --- the perpendicular fallback ----------------------------------------
	check("the secondary axis is the one the primary did not take",
		Facing.secondary_from_vec(Vector2(10, 1)) == Facing.DOWN)
	check("and vice versa",
		Facing.secondary_from_vec(Vector2(1, 10)) == Facing.RIGHT)
	check("there is no secondary when that axis is flat",
		Facing.secondary_from_vec(Vector2(10, 0)) == Facing.NONE)
	check("nor on the other axis",
		Facing.secondary_from_vec(Vector2(0, 10)) == Facing.NONE)

	# The two must never agree - a wall-slide that returns the direction you
	# are already stuck against is not a fallback, it is a loop.
	for v in [Vector2(10, 3), Vector2(-7, 2), Vector2(3, 10), Vector2(2, -9)]:
		var primary: String = Facing.from_vec(v)
		var secondary: String = Facing.secondary_from_vec(v)
		check("primary and secondary differ for %s" % v, primary != secondary,
			"both %s" % primary)

	# --- round trip ---------------------------------------------------------
	for dir in Facing.ALL:
		check("%s survives word -> vector -> word" % dir,
			Facing.from_vec(Facing.to_vec(dir)) == dir, Facing.to_vec(dir))

	check("an unknown word has no vector", Facing.to_vec("sideways") == Vector2.ZERO)
	check("and an empty one does not either", Facing.to_vec("") == Vector2.ZERO)

	check("the four words are the only directions",
		Facing.is_direction("up") and Facing.is_direction("down")
		and Facing.is_direction("left") and Facing.is_direction("right"))
	check("and nothing else is",
		not Facing.is_direction("") and not Facing.is_direction("sideways")
		and not Facing.is_direction("UP"))

	# --- EQUIVALENCE WITH THE CODE THIS REPLACED ---------------------------
	# _legacy_walk_animation() below is the exact body that lived in player.gd,
	# tank.gd, mage.gd, warrior.gd, healer.gd and pet.gd before Facing existed.
	# Keeping it HERE, in the test, is what turns "this refactor changed
	# nothing" from a claim into something that fails when it stops being true.
	#
	# It is the only copy of that code left in the project, and it is the only
	# place it belongs: a reference implementation exists to be disagreed with.
	var samples: Array[Vector2] = [
		Vector2(10, 1), Vector2(-10, 1), Vector2(1, 10), Vector2(1, -10),
		Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1),
		Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5),
		Vector2.ZERO, Vector2(0.001, 0.002), Vector2(-0.5, 0.5),
		Vector2(1000, 999), Vector2(999, 1000),
	]
	var mismatches: int = 0
	for v in samples:
		if "walk" + Facing.from_vec_total(v) != _legacy_walk_animation(v):
			mismatches += 1
			check("MISMATCH at %s" % v, false,
				"Facing gave %s, the old code gave %s"
				% ["walk" + Facing.from_vec_total(v), _legacy_walk_animation(v)])
	check("Facing agrees with the code it replaced, on %d vectors" % samples.size(),
		mismatches == 0, "%d disagreed" % mismatches)


func _legacy_walk_animation(dir: Vector2) -> String:
	# DO NOT "TIDY" THIS INTO A CALL TO FACING. It is deliberately the old
	# duplicated body, character for character, and the moment it delegates to
	# the thing it is checking, it checks nothing.
	if abs(dir.x) > abs(dir.y):
		return "walkright" if dir.x > 0 else "walkleft"
	else:
		return "walkdown" if dir.y > 0 else "walkup"


# =============================================================================
# PLAYERSTATS — the arithmetic lifted out of player.gd
# =============================================================================
# EXPECTED VALUES ARE WRITTEN OUT BY HAND, NOT DERIVED.
#
# `1.0 + (level - 1) * PlayerStats.DAMAGE_BONUS_PER_POINT` as an expectation
# would pass no matter what that constant became, because it is the same
# expression the function evaluates. These are the numbers the formulas produced
# before the split, computed separately. Change a constant deliberately and you
# change the number here too — that edit is the point.

func _test_player_stats() -> void:
	section("PLAYERSTATS")

	# --- pool maxima -------------------------------------------------------
	# Healer's real curve: hp_base 140, hp_per_lvl 7.
	check("level 1 gets exactly the base", PlayerStats.max_for(140, 7, 1) == 140,
		PlayerStats.max_for(140, 7, 1))
	check("level 10 gets base + 9 steps", PlayerStats.max_for(140, 7, 10) == 203,
		PlayerStats.max_for(140, 7, 10))
	check("level 99 gets base + 98 steps", PlayerStats.max_for(140, 7, 99) == 826,
		PlayerStats.max_for(140, 7, 99))
	check("a flat curve never grows", PlayerStats.max_for(20, 0, 50) == 20,
		PlayerStats.max_for(20, 0, 50))

	# --- defense tiers -----------------------------------------------------
	# The BOUNDARIES, not the middles. An off-by-one in the comparison would
	# leave every mid-tier level right and only the threshold wrong, which is
	# exactly the bug nobody notices while playing.
	check("defense 1 is Novice", PlayerStats.defense_tier(1)["name"] == "Novice")
	check("defense 19 is still Novice", PlayerStats.defense_tier(19)["name"] == "Novice")
	check("defense 20 is Trained", PlayerStats.defense_tier(20)["name"] == "Trained")
	check("defense 39 is still Trained", PlayerStats.defense_tier(39)["name"] == "Trained")
	check("defense 40 is Veteran", PlayerStats.defense_tier(40)["name"] == "Veteran")
	check("defense 60 is Hardened", PlayerStats.defense_tier(60)["name"] == "Hardened")
	check("defense 80 is Unbreakable", PlayerStats.defense_tier(80)["name"] == "Unbreakable")
	check("defense 999 is still only Unbreakable",
		PlayerStats.defense_tier(999)["name"] == "Unbreakable")

	# Reduction is capped at 50% on purpose — a hit always has to still matter.
	# This would catch a sixth tier being added above Unbreakable without the
	# consequence being thought through.
	for tier in PlayerStats.DEFENSE_TIERS:
		check("the %s tier reduces by at most half" % tier["name"],
			float(tier["reduction"]) <= 0.50, tier["reduction"])

	# The table is ordered highest-first and defense_tier() takes the first
	# match walking down. Re-order it and everyone silently gets Novice.
	var previous: int = 1 << 30
	for tier in PlayerStats.DEFENSE_TIERS:
		check("DEFENSE_TIERS is still ordered highest-first at %s" % tier["name"],
			int(tier["min_level"]) < previous,
			"%s came after %d" % [tier["min_level"], previous])
		previous = int(tier["min_level"])

	# --- damage ------------------------------------------------------------
	check("attack 1 is no bonus",
		is_equal_approx(PlayerStats.attack_damage_bonus(1), 1.0),
		PlayerStats.attack_damage_bonus(1))
	check("attack 101 is +50%",
		is_equal_approx(PlayerStats.attack_damage_bonus(101), 1.5),
		PlayerStats.attack_damage_bonus(101))
	check("magic uses the same rate as attack",
		is_equal_approx(PlayerStats.magic_damage_bonus(101),
			PlayerStats.attack_damage_bonus(101)),
		PlayerStats.magic_damage_bonus(101))

	check("a level 1 character has no damage multiplier",
		is_equal_approx(PlayerStats.damage_multiplier(1, 1), 1.0),
		PlayerStats.damage_multiplier(1, 1))
	check("attack 51 and magic 51 doubles damage",
		is_equal_approx(PlayerStats.damage_multiplier(51, 51), 2.0),
		PlayerStats.damage_multiplier(51, 51))
	check("attack and magic contribute independently",
		is_equal_approx(PlayerStats.damage_multiplier(51, 1), 1.5)
		and is_equal_approx(PlayerStats.damage_multiplier(1, 51), 1.5),
		"%s / %s" % [PlayerStats.damage_multiplier(51, 1),
			PlayerStats.damage_multiplier(1, 51)])

	# --- attack speed, and THE CAP ----------------------------------------
	# Callers DIVIDE a cooldown by this. Without the ceiling a high enough
	# agility divides the cooldown to nothing: an attack every frame, spawning
	# projectiles faster than they despawn. The cap is the only thing between
	# the game and that, so it gets tested at and well past the boundary.
	check("agility 1 attacks at base speed",
		is_equal_approx(PlayerStats.attack_speed_multiplier(1), 1.0),
		PlayerStats.attack_speed_multiplier(1))
	check("agility 51 is +50% speed",
		is_equal_approx(PlayerStats.attack_speed_multiplier(51), 1.5),
		PlayerStats.attack_speed_multiplier(51))
	check("agility 101 reaches the ceiling",
		is_equal_approx(PlayerStats.attack_speed_multiplier(101), 2.0),
		PlayerStats.attack_speed_multiplier(101))
	check("agility 500 does NOT exceed it",
		is_equal_approx(PlayerStats.attack_speed_multiplier(500), 2.0),
		PlayerStats.attack_speed_multiplier(500))
	check("and a cooldown divided by it never reaches zero",
		PlayerStats.attack_speed_multiplier(999999) > 0.0
		and PlayerStats.attack_speed_multiplier(999999) <= 2.0,
		PlayerStats.attack_speed_multiplier(999999))
	check("nor does it ever drop below base speed",
		is_equal_approx(PlayerStats.attack_speed_multiplier(0), 1.0),
		PlayerStats.attack_speed_multiplier(0))

	# --- skill XP ----------------------------------------------------------
	check("skill level 1 costs the base", PlayerStats.xp_needed_for_skill(1) == 100,
		PlayerStats.xp_needed_for_skill(1))
	check("skill level 2 costs 118", PlayerStats.xp_needed_for_skill(2) == 118,
		PlayerStats.xp_needed_for_skill(2))
	check("skill level 10 costs 443", PlayerStats.xp_needed_for_skill(10) == 443,
		PlayerStats.xp_needed_for_skill(10))
	check("skill level 50 costs 332826", PlayerStats.xp_needed_for_skill(50) == 332826,
		PlayerStats.xp_needed_for_skill(50))

	# The skill curve is steeper than the character curve on purpose — six
	# skills compete for the same play time. If they ever converge, someone has
	# edited one without the other.
	check("the skill curve is steeper than the character curve",
		PlayerStats.SKILL_XP_FACTOR > GameConstants.XP_GROWTH,
		"skill %s vs character %s" % [PlayerStats.SKILL_XP_FACTOR, GameConstants.XP_GROWTH])

	# --- regen -------------------------------------------------------------
	check("a big pool regenerates by percentage",
		is_equal_approx(PlayerStats.regen_rate_for(1000, 0.0167, 1.0), 16.7),
		PlayerStats.regen_rate_for(1000, 0.0167, 1.0))
	check("a small pool is carried by the floor",
		is_equal_approx(PlayerStats.regen_rate_for(20, 0.0167, 1.0), 1.0),
		PlayerStats.regen_rate_for(20, 0.0167, 1.0))
	check("an empty pool still returns the floor, not zero",
		is_equal_approx(PlayerStats.regen_rate_for(0, 0.0167, 1.0), 1.0),
		PlayerStats.regen_rate_for(0, 0.0167, 1.0))


# =============================================================================
# FORMATION — the ring enemies surround a player on
# =============================================================================
# Pure geometry, so all of it is checkable without a world. Which matters more
# than usual here: the formation is the thing that stops enemies piling into one
# spot, and "it looks about right when I fight three slimes" is the only test it
# has ever had.
#
# REWRITTEN AGAINST THE REAL API, and the reason is worth keeping. The first
# version of this block was written against a SQUARE GRID — SLOT_STRIDE,
# TILE_SIZE, world_position(anchor, slot, spacing), rings of 8/16/24 — and
# Formation has been a set of concentric CIRCLES since two days before this file
# was created. None of those five symbols exist. GDScript resolves a const on a
# class_name at PARSE time, so the file did not merely fail its formation
# checks: it failed to load, which means the whole suite, all of it, HAS NEVER
# RUN ONCE.
#
# That is this project's own recurring bug wearing the test suite's clothes. The
# thing written to catch "looks finished, does nothing" was itself finished-
# looking and doing nothing, and it said so in an error nobody read until the
# editor happened to try loading it.

func _test_formation() -> void:
	section("FORMATION")

	var offsets: Array[Vector2] = Formation.slot_offsets()

	# THE COUNT IS DERIVED, so the test derives it too rather than writing 40
	# down. slots_in_ring() is a consequence of the radius by design; pinning
	# the total here would mean every legitimate tuning of RING_RADIUS breaks
	# the suite, and a test that cries wolf is a test somebody deletes.
	var expected: int = 0
	for ring in range(1, Formation.RING_COUNT + 1):
		expected += Formation.slots_in_ring(ring)
	check("the rings produce as many slots as they say they do",
		offsets.size() == expected, "%d vs %d" % [offsets.size(), expected])
	check("slot_count agrees with the array",
		Formation.slot_count() == offsets.size(), Formation.slot_count())

	# EVERY SLOT STANDS ON ITS OWN RING. This is the invariant the whole model
	# rests on: ring_of() is the FIRST thing slot selection sorts by, so a slot
	# whose label disagrees with where it actually stands sends enemies to the
	# wrong rank while every individual position still looks reasonable.
	var off_ring: int = 0
	for i in range(offsets.size()):
		var want: float = Formation.ring_radius(Formation.ring_of(i))
		if absf(offsets[i].length() - want) > 0.001:
			off_ring += 1
	check("every slot stands at its own ring's radius", off_ring == 0,
		"%d slots off their ring" % off_ring)

	# RINGS STEP BY ONE BODY DIAMETER, which is what makes rank 2 touch the
	# backs of rank 1 rather than trying to stand inside them.
	check("each ring is one body diameter beyond the last",
		is_equal_approx(Formation.ring_radius(2) - Formation.ring_radius(1),
			Formation.BODY_RADIUS * 2.0),
		Formation.ring_radius(2) - Formation.ring_radius(1))

	# NOBODY OVERLAPS THEIR NEIGHBOUR, which is the entire point of the wedge
	# count. slots_in_ring() FLOORS, and flooring is the kind of thing a
	# refactor rounds "for accuracy" — which would put every ring exactly one
	# body over capacity and read in play as enemies standing inside each other.
	var overlapping: int = 0
	for ring in range(1, Formation.RING_COUNT + 1):
		var count: int = Formation.slots_in_ring(ring)
		var chord: float = 2.0 * Formation.ring_radius(ring) * sin(PI / float(count))
		if chord < Formation.BODY_RADIUS * 2.0:
			overlapping += 1
	check("no ring is packed tighter than a body's width", overlapping == 0,
		"%d rings overcrowded" % overlapping)

	# EVENLY SPACED AROUND EACH RING. Uneven spacing is how "they always come
	# from the left" happens, and it is invisible in a screenshot of one fight.
	#
	# The gap is taken with fposmod because bearing_of() answers in (-PI, PI]
	# and the ring wraps through it; a plain subtraction would report one
	# enormous negative gap per ring and pass anyway on the count.
	var uneven: int = 0
	for ring in range(1, Formation.RING_COUNT + 1):
		var bearings: Array[float] = []
		for i in range(offsets.size()):
			if Formation.ring_of(i) == ring:
				bearings.append(Formation.bearing_of(i))
		if bearings.size() < 2:
			continue
		var step: float = TAU / float(bearings.size())
		for j in range(1, bearings.size()):
			if absf(fposmod(bearings[j] - bearings[j - 1], TAU) - step) > 0.0001:
				uneven += 1
	check("slots are evenly spaced around each ring", uneven == 0,
		"%d uneven gaps" % uneven)

	# THE HALF-WEDGE PHASE. Ring 2 onward is rotated half a gap so the rank
	# behind stands in the gaps rather than directly behind backs — lined up it
	# reads as a queue, offset it reads as a crowd. That is a decision somebody
	# made on purpose, so it gets an assertion rather than a comment.
	for ring in range(2, Formation.RING_COUNT + 1):
		var first: int = -1
		for i in range(offsets.size()):
			if Formation.ring_of(i) == ring:
				first = i
				break
		if first < 0:
			continue
		check("ring %d starts half a gap round" % ring,
			absf(Formation.bearing_of(first)
				- PI / float(Formation.slots_in_ring(ring))) < 0.0001,
			Formation.bearing_of(first))

	# NO DUPLICATES. Two slots at one offset means two enemies standing in each
	# other, which is the exact failure the formation exists to prevent - and it
	# would look like a physics bug rather than a geometry one.
	var seen: Dictionary = {}
	var duplicates: int = 0
	for offset in offsets:
		if seen.has(offset):
			duplicates += 1
		seen[offset] = true
	check("no two slots share an offset", duplicates == 0, "%d duplicates" % duplicates)

	# NOTHING STANDS ON THE PLAYER.
	var on_anchor: int = 0
	for offset in offsets:
		if offset.is_zero_approx():
			on_anchor += 1
	check("no slot sits on the anchor", on_anchor == 0, "%d on the anchor" % on_anchor)

	# THERE IS DELIBERATELY NO MIRROR TEST, and the old grid version had one.
	# An odd ring — seven on ring 1 — cannot have opposites, and demanding them
	# would force even counts, which means rounding the wedge UP and putting
	# bodies inside each other. Even SPACING is the property that was actually
	# wanted; "every slot has an opposite" was a grid's way of spelling it.

	# --- world placement ----------------------------------------------------
	var anchor := Vector2(100, 200)
	check("an invalid slot puts you on the anchor itself",
		Formation.world_position(anchor, -1) == anchor,
		Formation.world_position(anchor, -1))
	check("and so does one past the end",
		Formation.world_position(anchor, 9999) == anchor)
	check("an out-of-range slot reports a ring worse than any real one",
		Formation.ring_of(9999) > Formation.RING_COUNT, Formation.ring_of(9999))

	# THE NEAREST RANK IS RING_RADIUS OUT, and that number is load bearing:
	# attack_range in baseenemy.gd is tuned against it, so a change here is a
	# change to whether a melee enemy can reach the player at all.
	var nearest: float = INF
	for i in range(Formation.slot_count()):
		nearest = minf(nearest, anchor.distance_to(Formation.world_position(anchor, i)))
	check("the closest slot is exactly RING_RADIUS out",
		is_equal_approx(nearest, Formation.RING_RADIUS), nearest)

	check("world_position is just the anchor plus the offset",
		Formation.world_position(anchor, 0) == anchor + Formation.offset_for(0))

	# The offsets are static and built once. slot_offsets() APPENDS to a static
	# array behind an is_empty() guard, so a second call that ever stopped
	# returning early would not error — it would silently double the formation.
	#
	# COMPARED AGAINST expected, NOT AGAINST offsets.size(). `offsets` is a
	# REFERENCE to that same static array, not a copy of it, so a doubling would
	# grow both sides of that comparison and the check would pass while cheerily
	# reporting eighty. A live reference compared against itself is the shape of
	# test this project keeps finding: present, green, and unable to fail.
	check("asking twice does not rebuild or extend the formation",
		Formation.slot_offsets().size() == expected,
		Formation.slot_offsets().size())

	# That aliasing gets an assertion of its own, because it is a real hazard
	# rather than a test artefact: any caller holding this array can append to
	# it and corrupt the formation for every enemy in the game.
	#
	# SHOWN BY MUTATION, NOT BY ==. The obvious spelling of this check is
	# `Formation.slot_offsets() == offsets`, and it is worthless: Array == in
	# GDScript compares CONTENTS, so it is equally true of a copy and can never
	# fail. Identity only shows up if you change one and look at the other, so a
	# sentinel goes on and comes straight back off. resize() restores the length
	# either way - if the array really is shared this repairs the formation, and
	# if it is a copy the append never reached the formation to begin with.
	var sentinel := Vector2(99999.0, 99999.0)
	offsets.append(sentinel)
	var aliased: bool = Formation.slot_offsets().size() == expected + 1
	offsets.resize(expected)
	check("slot_offsets hands out the shared array, not a copy", aliased,
		Formation.slot_offsets().size())
	check("and the formation is back to its own length afterwards",
		Formation.slot_offsets().size() == expected,
		Formation.slot_offsets().size())


# =============================================================================
# PETCONTROLLER
# =============================================================================
# This one touches the scene tree, unlike everything above it. That is allowed
# because it needs a tree and nothing else - no player, no world, no physics
# frame. Nodes created here are added to the same tree this suite runs in.

func _test_pet_controller() -> void:
	section("PETCONTROLLER")

	# --- the lookup --------------------------------------------------------
	var pet_id: String = _any_pet_item_id()
	check("a pet item exists to test with", pet_id != "", "no PET-type ItemData")
	if pet_id != "":
		check("a real pet item resolves to a scene",
			PetController.pet_scene_for(pet_id) != null, pet_id)

	check("an empty id resolves to nothing, and warns about nothing",
		PetController.pet_scene_for("") == null)

	# THE TWO REFUSALS BELOW ARE WRAPPED IN quietly(). Each one warns on purpose
	# - that is the refusal announcing itself - and the suite used to print an
	# apology here saying so. An apology in the output is not the fix.

	# A potion is not a pet. THIS IS THE CHECK THE SPLIT WAS FOR: the restore
	# path used to accept any item carrying a pet_scene without asking whether
	# it was a PET, so the two summon paths disagreed about what counts.
	var potion: ItemData = _any_item_of_type(ItemData.Type.CONSUMABLE)
	if potion != null:
		check("a consumable is not summonable as a pet",
			quietly(func() -> Variant: return PetController.pet_scene_for(potion.item_id)) == null,
			potion.item_id)

	check("an unknown id is not summonable",
		quietly(func() -> Variant: return PetController.pet_scene_for("notarealpet")) == null)

	# --- despawning --------------------------------------------------------
	# A REGRESSION TEST WITH A STORY. field.tscn had its pets CONTAINER in the
	# "pets" group, the same group the pets themselves join, so summoning a pet
	# in the field deleted the container out of the scene. The scene was fixed;
	# this is what stops the next mistyped group doing it again.
	var fake_pet := CharacterBody2D.new()
	fake_pet.name = "FakePet"
	fake_pet.add_to_group("pets")
	add_child(fake_pet)

	var not_a_pet := Node2D.new()
	not_a_pet.name = "PetsContainer"
	not_a_pet.add_to_group("pets")
	add_child(not_a_pet)

	# Skipping the container is what warns, and skipping it is the whole point.
	var freed: int = int(quietly(func() -> Variant: return PetController.despawn_all(get_tree())))

	check("despawn_all frees the pet", freed == 1, "freed %d" % freed)
	check("and the pet is actually going away",
		fake_pet.is_queued_for_deletion(), "not queued")
	check("but a non-pet in the pets group SURVIVES",
		is_instance_valid(not_a_pet) and not not_a_pet.is_queued_for_deletion(),
		"the field's pets container was deleted this way once")

	not_a_pet.queue_free()

	check("despawning an empty world frees nothing",
		PetController.despawn_all(get_tree()) == 0)
	check("and a null tree is survivable rather than a crash",
		PetController.despawn_all(null) == 0)


func _any_pet_item_id() -> String:
	for item in ItemRegistry.get_all_items():
		if item != null and item.type == ItemData.Type.PET and item.pet_scene != null:
			return item.item_id
	return ""


func _any_item_of_type(wanted: ItemData.Type) -> ItemData:
	for item in ItemRegistry.get_all_items():
		if item != null and item.type == wanted:
			return item
	return null


# =============================================================================
# ITEMSTACK
# =============================================================================

func _test_itemstack() -> void:
	section("ITEMSTACK")

	var item: ItemData = _any_stackable_item()
	if item == null:
		check("a stackable item exists to test with", false,
			"no stackable ItemData under data/items")
		return

	var stack := ItemStack.new(item, 1)
	check("a new stack holds what it was given", stack.quantity == 1, stack.quantity)
	check("and is not empty", not stack.is_empty())

	# add_to_stack returns the LEFTOVER, which is the part that matters: a caller
	# that ignores it silently destroys items.
	var leftover: int = stack.add_to_stack(item.max_stack)
	check("filling past max_stack returns the overflow",
		leftover == 1, "leftover %d from max_stack %d" % [leftover, item.max_stack])
	check("and the stack sits exactly at the ceiling",
		stack.quantity == item.max_stack, stack.quantity)
	check("a full stack says so", stack.is_full())

	var removed: int = stack.remove_quantity(item.max_stack + 50)
	check("removing more than is there removes only what is there",
		removed == item.max_stack, "removed %d" % removed)
	check("and leaves it empty", stack.quantity == 0, stack.quantity)

	# THE SAVE ROUND TRIP. Saves store {item_id, quantity} and rehydrate against
	# the registry — if this ever stops being lossless, every save is wrong.
	var original := ItemStack.new(item, 3)
	var rebuilt := ItemStack.from_dict(original.to_dict())
	check("a stack survives to_dict/from_dict", rebuilt != null, original.to_dict())
	if rebuilt != null:
		check("with the same item", rebuilt.data.item_id == item.item_id, rebuilt.data.item_id)
		check("and the same quantity", rebuilt.quantity == 3, rebuilt.quantity)

	# JSON has no integer type, so a quantity that has been through a server
	# round trip arrives as 3.0. from_dict has to coerce it; without the int()
	# cast the assignment to a typed int field is what would fail.
	var floaty := ItemStack.from_dict({"item_id": item.item_id, "quantity": 3.0})
	check("a float quantity rehydrates as an int 3",
		floaty != null and floaty.quantity == 3 and typeof(floaty.quantity) == TYPE_INT,
		"got %s" % (floaty.quantity if floaty != null else "null"))

	# An unknown id must never produce a stack CLAIMING to be that item.
	#
	# Not "returns null": ItemRegistry.get_item() substitutes FALLBACK_ITEM_ID
	# when error_item.tres exists. It does not exist today, so from_dict returns
	# null — but asserting null would mean this check silently stopped testing
	# anything the day someone added the fallback item.
	# quietly(): the registry warns about the unknown id, which is it doing its
	# job. See the note on quietly() for why that does not belong in the output.
	var ghost: ItemStack = quietly(
		func() -> Variant: return ItemStack.from_dict({"item_id": "notarealitem", "quantity": 1}))
	check("an unknown item_id never rehydrates as that item",
		ghost == null or ghost.data.item_id != "notarealitem",
		ghost.data.item_id if ghost != null else "null")

	check("a dict missing quantity rehydrates as null",
		ItemStack.from_dict({"item_id": item.item_id}) == null)


func _any_stackable_item() -> ItemData:
	# get_all_items(), not get_all_ids() — the registry returns the resources.
	for item in ItemRegistry.get_all_items():
		if item != null and item.stackable and item.max_stack > 1:
			return item
	return null


# =============================================================================
# RANKS — the client's half of the server's ordering
# =============================================================================

func _test_ranks() -> void:
	section("RANKS")

	var saved_role: String = Api.role

	Api.role = "player"
	check("a player is at least a player", Api.role_at_least("player"))
	check("but not a mod", not Api.role_at_least("mod"))

	Api.role = "mod"
	check("a mod is at least a mod", Api.role_at_least("mod"))
	check("and outranks a player", Api.role_at_least("player"))
	check("but is not a dev", not Api.role_at_least("dev"))

	Api.role = "dev"
	check("a dev outranks a mod", Api.role_at_least("mod"))
	check("but is not the owner", not Api.role_at_least("owner"))

	Api.role = "owner"
	check("the owner outranks everything", Api.role_at_least("dev"))

	# FAILS LOW, BOTH WAYS. A response from a newer server naming a rank this
	# build has never heard of must not read as more privilege than the player
	# has — and asking about a rank that does not exist must deny, not crash.
	Api.role = "superuser"
	check("an unknown rank grants nothing", not Api.role_at_least("player"), Api.role)

	Api.role = "owner"
	check("an unknown requirement denies", not Api.role_at_least("wizard"))

	# There are exactly four ranks and nothing else is one. This is the check
	# that fails if a fifth is ever added to app.py without being added here -
	# a client that does not know a rank must treat it as no privilege at all,
	# and the only way that stays true is if the two lists agree.
	# Every real rank is at least a player, so this passes for all four and
	# fails for anything role_at_least() does not recognise.
	var expected: PackedStringArray = ["player", "mod", "dev", "owner"]
	for rank in expected:
		Api.role = rank
		check("%s is a rank this build knows" % rank, Api.role_at_least("player"), rank)

	# ...and the owner outranks or equals every one of them.
	Api.role = "owner"
	for rank in expected:
		check("the owner satisfies a %s requirement" % rank,
			Api.role_at_least(rank), rank)

	# THE DEBUG KEYS ARE STAFF-ONLY. They hand out gear, pets, lusions and skill
	# XP - all things a player is meant to earn, and a pet in particular is loot.
	#
	# Asserted against Api.DEBUG_KEYS_MIN_ROLE rather than the literal "mod", so
	# this tests the policy player.gd actually applies instead of a second copy
	# of it that can drift.
	#
	# This is a rule, not a defence. The gate is client-side and the backpack
	# ledger is client-asserted, so it stops an honest player in a debug build
	# and nothing more. See _staff_debug_allowed() in player.gd.
	Api.role = "player"
	check("a player cannot use the debug keys",
		not Api.role_at_least(Api.DEBUG_KEYS_MIN_ROLE), Api.DEBUG_KEYS_MIN_ROLE)
	for rank in ["mod", "dev", "owner"]:
		Api.role = rank
		check("a %s can" % rank, Api.role_at_least(Api.DEBUG_KEYS_MIN_ROLE), rank)

	Api.role = saved_role


# =============================================================================
# COLLISION CONTRACT
# =============================================================================

# THE TEST THAT WOULD HAVE CAUGHT THE FIRE PET ON DAY ONE.
#
# petfireprojectile.tscn shipped with collision_mask = 4 ("player"), copied from
# the ENEMY fire sprite's projectile, where that is correct. Enemies sit on layer
# 8. Godot reports a contact only when `area.mask & body.layer` is non-zero, and
# 4 & 8 is 0 — so body_entered never fired, _try_damage() was never called, and
# the pet's orb flew through everything it was aimed at. The script was right the
# whole time. Nothing logged. Nothing errored. The pet simply did nothing, which
# is indistinguishable from a pet that is missing its target.
#
# A mask is two numbers in a .tscn with no natural place to be wrong out loud.
# This is that place.
const PLAYER_PROJECTILE_SCENES := [
	"res://scene/projectiles/slashwave.tscn",
	"res://scene/projectiles/turretprojectile.tscn",
	"res://scene/projectiles/spelltargetcircle.tscn",
	"res://scene/pets/petprojectiles/petarrow.tscn",
	"res://scene/pets/petprojectiles/petfireprojectile.tscn",
	"res://scene/pets/petprojectiles/petmagicprojectile.tscn",
	"res://scene/pets/petprojectiles/petpoisonball.tscn",
	"res://scene/pets/petprojectiles/petvine.tscn",
]

const ENEMY_PROJECTILE_SCENES := [
	"res://scene/projectiles/arrow.tscn",
	"res://scene/projectiles/poisonarrow.tscn",
	"res://scene/projectiles/poisonball.tscn",
	"res://scene/projectiles/fireprojectile.tscn",
	"res://scene/projectiles/magicprojectile.tscn",
	"res://scene/projectiles/bossprojectile.tscn",
	"res://scene/projectiles/secondbossprojectile.tscn",
	"res://scene/projectiles/vine.tscn",

	# THE NINE PUDDLES, listed one by one on purpose.
	#
	# They were one scene recoloured at runtime, so one row here covered all of
	# them. They are nine files now, each meant to be opened and tuned — which
	# is nine chances for someone adjusting ice to clear a layer field they did
	# not mean to touch. A pool on the wrong layer is invisible when it breaks:
	# it draws, it fades on time, and it never hurts anybody.
	"res://scene/projectiles/poisonpuddle.tscn",
	"res://scene/projectiles/firepuddle.tscn",
	"res://scene/projectiles/icepuddle.tscn",
	"res://scene/projectiles/earthpuddle.tscn",
	"res://scene/projectiles/waterpuddle.tscn",
	"res://scene/projectiles/darkpuddle.tscn",
	"res://scene/projectiles/lightningpuddle.tscn",
	"res://scene/projectiles/lightpuddle.tscn",
	"res://scene/projectiles/windpuddle.tscn",

	# THE FORTY-EIGHT ELEMENTAL VARIANTS, six per family.
	#
	# Same reason as the puddles above, with more at stake: these are full
	# copies, so a layer or mask edited on one of them does NOT follow from the
	# base scene. A variant whose mask lost the player bit is an arrow that flies
	# through everyone it is aimed at and reports nothing at all - the exact
	# failure this whole section was written for, multiplied by forty-eight.
	# bush sniper
	"res://scene/projectiles/darkarrow.tscn",
	"res://scene/projectiles/eartharrow.tscn",
	"res://scene/projectiles/icearrow.tscn",
	"res://scene/projectiles/lightarrow.tscn",
	"res://scene/projectiles/waterarrow.tscn",
	"res://scene/projectiles/windarrow.tscn",
	# small slime
	"res://scene/projectiles/darkpoisonarrow.tscn",
	"res://scene/projectiles/earthpoisonarrow.tscn",
	"res://scene/projectiles/icepoisonarrow.tscn",
	"res://scene/projectiles/lightpoisonarrow.tscn",
	"res://scene/projectiles/waterpoisonarrow.tscn",
	"res://scene/projectiles/windpoisonarrow.tscn",
	# large slime
	"res://scene/projectiles/darkpoisonball.tscn",
	"res://scene/projectiles/earthpoisonball.tscn",
	"res://scene/projectiles/icepoisonball.tscn",
	"res://scene/projectiles/lightpoisonball.tscn",
	"res://scene/projectiles/waterpoisonball.tscn",
	"res://scene/projectiles/windpoisonball.tscn",
	# fire sprite
	"res://scene/projectiles/darkfireprojectile.tscn",
	"res://scene/projectiles/earthfireprojectile.tscn",
	"res://scene/projectiles/icefireprojectile.tscn",
	"res://scene/projectiles/lightfireprojectile.tscn",
	"res://scene/projectiles/waterfireprojectile.tscn",
	"res://scene/projectiles/windfireprojectile.tscn",
	# electric sprite
	"res://scene/projectiles/darkmagicprojectile.tscn",
	"res://scene/projectiles/earthmagicprojectile.tscn",
	"res://scene/projectiles/icemagicprojectile.tscn",
	"res://scene/projectiles/lightmagicprojectile.tscn",
	"res://scene/projectiles/watermagicprojectile.tscn",
	"res://scene/projectiles/windmagicprojectile.tscn",
	# bush mage
	"res://scene/projectiles/darkvine.tscn",
	"res://scene/projectiles/firevine.tscn",
	"res://scene/projectiles/icevine.tscn",
	"res://scene/projectiles/lightvine.tscn",
	"res://scene/projectiles/watervine.tscn",
	"res://scene/projectiles/windvine.tscn",
	# boss pillar
	"res://scene/projectiles/earthbossprojectile.tscn",
	"res://scene/projectiles/firebossprojectile.tscn",
	"res://scene/projectiles/icebossprojectile.tscn",
	"res://scene/projectiles/lightbossprojectile.tscn",
	"res://scene/projectiles/waterbossprojectile.tscn",
	"res://scene/projectiles/windbossprojectile.tscn",
	# boss gate spike
	"res://scene/projectiles/earthsecondbossprojectile.tscn",
	"res://scene/projectiles/firesecondbossprojectile.tscn",
	"res://scene/projectiles/icesecondbossprojectile.tscn",
	"res://scene/projectiles/lightsecondbossprojectile.tscn",
	"res://scene/projectiles/watersecondbossprojectile.tscn",
	"res://scene/projectiles/windsecondbossprojectile.tscn",
]

# Bit VALUES, not indices: layer N in the Project Settings list is 1 << (N - 1).
const LAYER_PLAYER := 4            # layer 3
const LAYER_ENEMIES := 8           # layer 4
const LAYER_PLAYERPROJECTILE := 32 # layer 6
const LAYER_ENEMYPROJECTILE := 64  # layer 7


func _test_collision_contract() -> void:
	section("COLLISION CONTRACT — can each projectile see what it damages?")

	# EVERY NUMBER BELOW IS A BIT POSITION, and bit positions mean nothing on
	# their own. Reordering the layer list in Project Settings renames the bits
	# without touching a single scene, so every mask in the project would keep
	# its value and quietly change its meaning. Check the names first, so a
	# reorder fails here rather than in combat.
	_check_layer_name(3, "player")
	_check_layer_name(4, "enemies")
	_check_layer_name(6, "playerprojectile")
	_check_layer_name(7, "enemyprojectile")

	for path in PLAYER_PROJECTILE_SCENES:
		_check_projectile(path, LAYER_PLAYERPROJECTILE, "playerprojectile",
			LAYER_ENEMIES, "enemies")

	for path in ENEMY_PROJECTILE_SCENES:
		_check_projectile(path, LAYER_ENEMYPROJECTILE, "enemyprojectile",
			LAYER_PLAYER, "player")


func _check_layer_name(index: int, expected: String) -> void:
	var key: String = "layer_names/2d_physics/layer_%d" % index
	var actual: String = str(ProjectSettings.get_setting(key, ""))
	check("physics layer %d is still '%s'" % [index, expected],
		actual == expected, "project settings say '%s'" % actual)


func _check_projectile(path: String, want_layer: int, layer_name: String,
		want_mask_bit: int, target_name: String) -> void:
	var file_name: String = path.get_file()

	if not ResourceLoader.exists(path):
		check("%s exists" % file_name, false, path)
		return

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		check("%s loads as a PackedScene" % file_name, false, path)
		return

	# instantiate() builds the node without entering the tree, so _ready() does
	# not run and nothing this touches has side effects. free() rather than
	# queue_free() because there is no tree to queue against.
	var node: Node = packed.instantiate()
	var area := node as CollisionObject2D
	if area == null:
		check("%s root is a CollisionObject2D" % file_name, false,
			"got %s" % node.get_class())
		node.free()
		return

	var layer: int = area.collision_layer
	var mask: int = area.collision_mask
	node.free()

	check("%s lives on %s" % [file_name, layer_name],
		layer == want_layer, "layer is %d, expected %d" % [layer, want_layer])

	# THE ONE THAT MATTERS. A projectile whose mask misses its target's layer
	# never receives a collision signal at all, so no amount of correct script
	# below it will ever run.
	check("%s can see %s" % [file_name, target_name],
		(mask & want_mask_bit) != 0,
		"mask %d does not include %d" % [mask, want_mask_bit])
