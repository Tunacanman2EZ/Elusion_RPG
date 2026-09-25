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
	_test_settings()
	_test_map_landmarks()
	_test_boss_arena_exits()
	_test_staff_panel()
	_test_collision_contract()
	_test_frame_budget()


# =============================================================================
# THE FRAME BUDGET
# =============================================================================
# A game holds its frame rate or it does not, and the whole question is decided
# by what runs every frame. Everything else in this file checks that a number
# is right; this checks that the game is still fast enough to show it.
#
# WHY IT IS A TEST AND NOT A PROFILING SESSION. Profiling tells you what is slow
# today. A test tells you the day something GOT slow, which is the only version
# of the question that helps on a project meant to run for years - by the time
# a hitch is bad enough to feel, it has usually been growing for months and
# nobody can say which change caused it.
#
# THE THRESHOLDS ARE DELIBERATELY LOOSE. These run on whatever machine the
# developer has, possibly with a build and a browser fighting them for CPU, so
# a tight bound would fail for reasons that have nothing to do with the code.
# Each one is set where crossing it means something structural changed - a
# per-frame lookup added to a loop, a pooled list quietly turned back into a
# rebuilt one - not where a number drifted by a millisecond.

# 33.3ms is a frame at 30fps. Not 60: 30 is the floor this game promises, and a
# floor is what a budget should be measured against.
const FRAME_BUDGET_MS := 33.3


func _test_frame_budget() -> void:
	section("FRAME BUDGET — what every frame costs")

	# --- space queries ----------------------------------------------------
	# The enemy AI runs a raycast and a shape query per enemy per physics
	# frame. Measured at about 2us and 4us, which is why it was left alone -
	# eighty enemies is under 2% of a frame. This check exists so that stays
	# true: a physics layer misconfigured into testing every body, or a
	# collision mask widened by accident, shows up here as a query that costs
	# ten times what it should.
	var space := get_viewport().world_2d.direct_space_state
	var ray := PhysicsRayQueryParameters2D.new()
	ray.collide_with_areas = false
	var runs := 2000
	var started := Time.get_ticks_usec()
	for i in range(runs):
		ray.from = Vector2(float(i % 400), 0.0)
		ray.to = Vector2(float(i % 400) + 200.0, 300.0)
		space.intersect_ray(ray)
	var ray_us := float(Time.get_ticks_usec() - started) / runs

	# 40us is twenty times the measured cost. A ray that takes longer than
	# that is not drift, it is a different query.
	check("a raycast is still cheap enough to do per enemy per frame",
		ray_us < 40.0, "%.2f us each" % ray_us)

	# --- the kingdom board ------------------------------------------------
	# The heaviest list in the game: up to two hundred rows, refreshed on a
	# timer whether or not anybody is looking at it.
	var board_scene: PackedScene = load("res://scene/ui/kingdom/kingdomboard.tscn")
	if board_scene == null:
		check("the kingdom board scene loads", false, "missing")
		return
	var board: Control = board_scene.instantiate()
	add_child(board)

	var rows: Array = []
	for i in range(200):
		rows.append({"username": "player%04d" % i, "contributed": 1_000_000 - i,
			"lusions": i, "deaths": i % 50, "rank": i + 1})

	# FIRST PAINT IS SPREAD ACROSS FRAMES on purpose - building two hundred
	# rows in one go measured at 79ms, which is two and a half frames of
	# stutter every time the panel opened. Each slice must fit in a frame, and
	# the whole board must still finish.
	var worst_slice := 0.0
	var slices := 0
	board._render_rows(rows)
	while true:
		slices += 1
		if board._rows_pending.is_empty():
			break
		var slice_start := Time.get_ticks_usec()
		board._render_rows(board._rows_pending, board._rows_done)
		worst_slice = maxf(worst_slice,
			float(Time.get_ticks_usec() - slice_start) / 1000.0)
		if slices > 500:
			break

	check("no slice of the board's first paint eats a frame",
		worst_slice < FRAME_BUDGET_MS,
		"worst slice %.2f ms against a %.1f ms frame" % [worst_slice, FRAME_BUDGET_MS])
	check("and the board finishes building",
		board.board_list.get_child_count() == 200,
		"%d rows" % board.board_list.get_child_count())

	# A REFRESH REUSES THE ROWS. If somebody changes _render_rows() back to
	# freeing and rebuilding, this is the number that moves - a refill of two
	# hundred rows measured at about 13ms, a rebuild at 79ms.
	var refresh_start := Time.get_ticks_usec()
	board._render_rows(rows)
	var refresh_ms := float(Time.get_ticks_usec() - refresh_start) / 1000.0
	check("a board refresh fits inside one frame",
		refresh_ms < FRAME_BUDGET_MS,
		"%.2f ms against a %.1f ms frame" % [refresh_ms, FRAME_BUDGET_MS])

	# AND IT DOES NOT GROW WITH THE SERVER. The panel's cost is set by rows on
	# screen, which the server caps; a year of ledger rows cannot reach it.
	var few: Array = rows.slice(0, 10)
	board._render_rows(few)
	var small_start := Time.get_ticks_usec()
	board._render_rows(few)
	var small_ms := float(Time.get_ticks_usec() - small_start) / 1000.0
	check("ten rows cost a fraction of two hundred",
		small_ms < refresh_ms, "%.2f ms vs %.2f ms" % [small_ms, refresh_ms])

	board.queue_free()

	# --- what one player costs the server ---------------------------------
	# THE ONLY BUDGET HERE THAT IS NOT ABOUT THIS MACHINE, and the one that
	# scales with players rather than with content.
	#
	# The load test puts the read ceiling around 800 requests a second on four
	# workers. Divide that by what one client asks for and you get how many
	# people the box holds: at 0.55 req/s it is about fifteen hundred, at 3
	# req/s it is under three hundred. Nobody notices adding a panel that polls
	# every two seconds; everybody notices the box it lands on.
	#
	# READ OFF THE REAL CONSTANTS, so this goes stale the moment somebody
	# changes an interval - which is exactly when the arithmetic stops being
	# true and somebody should look at it again.
	var always: float = (
		1.0 / Api.HEARTBEAT_SECONDS
		+ 1.0 / load("res://src/ui/characterhud.gd").BROADCAST_POLL_SECONDS
		+ 1.0 / load("res://src/systems/skilltrainer.gd").FLUSH_INTERVAL
	)
	var with_chat: float = always + 1.0 / load(
		"res://src/ui/chat/chatpanel.gd").POLL_SECONDS

	# One request a second per player is the line. It is not a hardware limit,
	# it is the point past which a single box stops holding a thousand people -
	# and crossing it should be a decision somebody made on purpose.
	check("a player sitting in the world stays well under 1 req/s",
		always < 0.5, "%.3f req/s with nothing open" % always)
	check("and under it with chat open, which is most of the time",
		with_chat < 1.0, "%.3f req/s" % with_chat)

	# The counter the perf overlay reads has to actually count.
	var before: int = Api.requests_total()
	Api._note_request()
	check("the request counter counts", Api.requests_total(), before + 1)
	check("and reports a rate over its window",
		Api.requests_per_second() > 0.0,
		"%.3f req/s" % Api.requests_per_second())


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


func require_script(path: String, what: String) -> Script:
	"""Load a script a whole section depends on, or fail the section out loud.

	WHY THIS EXISTS. A section that does `load(...)` and calls straight into the
	result dies on the first line when the file is missing or will not compile.
	GDScript prints one error to stderr and unwinds the rest of the section -
	so the report prints the heading, nothing under it, and moves on. Zero
	checks ran and zero checks failed, which reads exactly like a clean pass.

	That is the same hole as the suites that printed no summary line: work that
	silently did not happen, reported as work that happened fine. A missing
	subject is a FAILURE, and it has to say so in the one place anybody looks.
	"""
	var script: Script = load(path) as Script
	if script == null:
		check("%s loads at all" % what, false,
			"%s is missing or will not compile - every check below it was SKIPPED" % path)
	return script


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

	_test_pet_drops_can_pay_out(data)
	_test_every_exported_constant(constants)


# =============================================================================
# A PET ROLL THAT CANNOT PAY OUT
# =============================================================================
# ELEVEN ENEMIES ROLLED FOR A PET THEY COULD NOT DROP, and the six elemental
# bosses among them are the hardest content in the game - up to 8,216 hp, more
# than the base boss that drops petboss at 1 in 72. A player could farm
# earthboss forever and the roll would never once be reachable.
#
# The cause was an omission, not a decision: pet_drop_id defaults to "" and a
# .tres omits any property equal to its default, so an elemental variant copied
# from a sibling that had not set it yet simply has no line, and looks exactly
# like one that never wanted a pet. roll_pet() returns on the empty id before it
# ever reads the odds, so nothing errors, nothing logs, and the odds in the
# exporter's own listing read as though they were live.
#
# WHY THIS BELONGS HERE AND NOT IN THE EXPORTER'S WARNING. That warning existed
# and said the right thing, and it was read as harmless - it ends "harmless
# while the pets are unauthored", which was true once and had quietly stopped
# being true: petboss.tres and petmage.tres both exist. A warning that explains
# itself away gets skimmed. A failing check does not.


func _test_pet_drops_can_pay_out(data: Dictionary) -> void:
	var items: Array = data.get("items", [])
	var known := {}
	for item in items:
		known[str(item.get("item_id", ""))] = true

	# Every enemy that rolls for a pet must be able to award one. Read off the
	# EXPORT rather than the .tres files, because the export is what the server
	# reads too - so this compares the thing both sides actually use.
	var dead: Array[String] = []
	for enemy in data.get("enemies", []):
		if not bool(enemy.get("grants_rewards", true)):
			continue
		if int(enemy.get("pet_odds", 0)) <= 0:
			continue
		var pet: String = str(enemy.get("pet_drop_id", ""))
		var rare: String = str(enemy.get("rare_pet_drop_id", ""))
		if pet == "":
			dead.append("%s rolls 1/%d for nothing"
				% [enemy.get("enemy_id"), int(enemy.get("pet_odds", 0))])
		elif not known.has(pet):
			dead.append("%s names pet '%s', which is not an item"
				% [enemy.get("enemy_id"), pet])
		# The rare slot is optional, but a NAMED one that does not exist is the
		# same silent dead end one level down.
		if rare != "" and not known.has(rare):
			dead.append("%s names rare pet '%s', which is not an item"
				% [enemy.get("enemy_id"), rare])

	dead.sort()
	check("every enemy that rolls for a pet can actually drop one",
		dead.is_empty(), "\n         ".join(dead))


# =============================================================================
# THE REST OF THE CONTRACT
# =============================================================================
# The block above checks six constants by hand. The contract carries thirty-one,
# and the eighteen nobody was comparing included every number this year's
# economy work added: the coin ladder, the jackpot dice, the lusion weight, the
# revive floor, the trade tax. Each one is authored in a GDScript const, copied
# into gamedata.json by the exporter, and then read by Flask - so each one is a
# number that can be edited in the game and left stale on the server, silently,
# with no disagreement anybody can see.
#
# A TABLE RATHER THAN EIGHTEEN MORE HAND-WRITTEN CHECKS. The hand-written form
# is why there were only six: each is five lines, and nobody adds five lines
# when they add a constant. A row is one line, so the next constant has a real
# chance of being covered.
#
# THE SOURCE SCRIPT IS NAMED PER ROW because these live in three different
# files, and reading the constant off the script that DEFINES it is the whole
# point - comparing gamedata.json to a copy in this file would just be a third
# place for the number to go stale.

func _test_every_exported_constant(constants: Dictionary) -> void:
	section("THE EXPORTED CONTRACT — every constant, both sides")

	var sources := {
		"enemy": (load("res://src/enemies/baseenemy.gd") as GDScript).get_script_constant_map(),
		"game": (load("res://src/systems/gameconstants.gd") as GDScript).get_script_constant_map(),
		"char": (load("res://src/systems/characterdata.gd") as GDScript).get_script_constant_map(),
		"stats": (load("res://src/characters/playerstats.gd") as GDScript).get_script_constant_map(),
	}

	# [contract key, source, constant name]. Mirrors _export_constants() in
	# exportgamedata.gd - if a row is added there, add one here.
	var rows := [
		["gold_tier_ratio", "enemy", "GOLD_TIER_RATIO"],
		["gold_base_unit", "enemy", "GOLD_BASE_UNIT"],
		["gold_spread", "enemy", "GOLD_SPREAD"],
		["gold_denomination_ids", "enemy", "GOLD_DENOMINATION_IDS"],
		["gold_jackpot_dice", "enemy", "GOLD_JACKPOT_DICE"],
		["gold_jackpot_faces", "enemy", "GOLD_JACKPOT_FACES"],
		["gold_jackpot_min_tier", "enemy", "GOLD_JACKPOT_MIN_TIER"],
		["gold_jackpot_multipliers", "enemy", "GOLD_JACKPOT_MULTIPLIERS"],
		["lusion_gold_value", "game", "LUSION_GOLD_VALUE"],
		["revive_cost", "game", "REVIVE_COST"],
		["revive_gold_rate", "game", "REVIVE_GOLD_RATE"],
		["revive_gold_minimum", "game", "REVIVE_GOLD_MINIMUM"],
		["dupe_pet_lusions", "game", "DUPE_PET_LUSIONS"],
		["kingdom_tax_rate", "game", "KINGDOM_TAX_RATE"],
		["kingdom_tax_minimum", "game", "KINGDOM_TAX_MINIMUM"],
	]

	for row in rows:
		var key: String = String(row[0])
		var mine = sources[String(row[1])].get(String(row[2]))
		var theirs = constants.get(key)
		check("%s matches the game's %s" % [key, String(row[2])],
			theirs != null and mine != null and _same_number(mine, theirs),
			"contract %s, game %s" % [theirs, mine])

	# THE LADDER IS ONLY USEFUL IF THE COINS EXIST. The same check the two
	# legacy gold ids get above, for the eight that replaced them - a
	# denomination naming an item ItemRegistry has not got is a coin the server
	# will make change in and the game cannot draw.
	for item_id in BaseEnemy.GOLD_DENOMINATION_IDS:
		check("the '%s' coin exists" % String(item_id),
			ItemRegistry.has_item(String(item_id)), String(item_id))

	# And it must be ordered richest-first with no ties, because make_change()
	# walks it in order and a ladder out of order makes change that is wrong
	# rather than merely ugly.
	var previous_value: int = -1
	for item_id in BaseEnemy.GOLD_DENOMINATION_IDS:
		var coin: ItemData = ItemRegistry.get_item(String(item_id))
		if coin == null:
			continue
		var worth: int = int(coin.value)
		if previous_value >= 0:
			check("%s is worth less than the coin above it" % String(item_id),
				worth < previous_value, "%d then %d" % [previous_value, worth])
		previous_value = worth

	# The multiplier table has to have one entry per possible number of sixes,
	# or a lucky roll indexes past the end of it.
	check("there is a jackpot multiplier for every dice outcome",
		BaseEnemy.GOLD_JACKPOT_MULTIPLIERS.size() == BaseEnemy.GOLD_JACKPOT_DICE + 1,
		"%d multipliers for %d dice" % [BaseEnemy.GOLD_JACKPOT_MULTIPLIERS.size(),
			BaseEnemy.GOLD_JACKPOT_DICE])


func _same_number(mine, theirs) -> bool:
	"""Compare a GDScript constant with what came back out of JSON.

	JSON HAS NO INTEGER TYPE and no float/int distinction the way GDScript does,
	so 0.8 can come back as a float and 5 as an int-shaped float. Comparing with
	== would fail on types rather than on values, which is a test that cries
	wolf until somebody deletes it.

	Arrays are compared element by element, because an exported array of ids is
	a PackedStringArray on one side and a plain Array on the other and those are
	never == either.

	AND EACH ELEMENT GOES THROUGH THIS SAME FUNCTION rather than through str().
	The first version stringified them, which is right for ids and wrong for
	numbers: JSON parsed the jackpot multipliers [1, 1, 1, 4, 12, 45] back as
	floats, and "1.0" != "1" reported a mismatch between a table and itself."""
	if mine is Array or mine is PackedStringArray or mine is PackedInt32Array \
			or mine is PackedFloat64Array:
		if not (theirs is Array):
			return false
		if mine.size() != theirs.size():
			return false
		for index in range(mine.size()):
			if not _same_number(mine[index], theirs[index]):
				return false
		return true
	# Ids and other text, once the array case has been dealt with.
	if mine is String or mine is StringName or theirs is String \
			or theirs is StringName:
		return str(mine) == str(theirs)
	if mine is float or theirs is float:
		return absf(float(mine) - float(theirs)) < 0.000001
	return int(mine) == int(theirs)


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
# SETTINGS - the frame-pacing rules, and every setting has a control
# =============================================================================
# Two things this guards. First, the normalisers: an options.cfg from before
# vsync became a mode stores a bool, and it has to keep meaning what it meant.
# Second, the contract the settings file states in its own header - "adding a
# setting is one line in DEFAULTS and one control in optionsscreen.tscn" - is
# exactly the kind of promise that breaks silently, and this checks it.

func _test_settings() -> void:
	section("SETTINGS")

	# --- the regression, pinned ------------------------------------------
	# The tearing band came back because code chose a frame cap on its own -
	# ceil(refresh) - 1 - and a cap near the refresh rate is what makes a tear
	# seam slow enough to see. These two lines are the fix, stated as facts.
	check("the default vsync is on", Settings.DEFAULTS["vsync"] == "on", Settings.DEFAULTS["vsync"])
	check("and the default cap is no cap", Settings.DEFAULTS["frame_cap"] == 0, Settings.DEFAULTS["frame_cap"])
	check("Unlimited is the first cap the picker offers", Settings.FRAME_CAPS[0] == 0)

	# --- migration --------------------------------------------------------
	check("an old vsync=true means on", Settings.normalise_vsync(true) == "on")
	check("an old vsync=false means off", Settings.normalise_vsync(false) == "off")
	check("the string 'false' too", Settings.normalise_vsync("false") == "off")
	check("case does not matter", Settings.normalise_vsync("Adaptive") == "adaptive")
	check("nonsense becomes the default", Settings.normalise_vsync("banana") == "on")
	check("a negative cap is no cap", Settings.normalise_frame_cap(-5) == 0)

	# --- the mode table round-trips ------------------------------------------
	var lost: Array = []
	for mode_name in Settings.VSYNC_MODES:
		if Settings.vsync_name_for(Settings.vsync_mode_for(mode_name)) != mode_name:
			lost.append(mode_name)
	check("every mode survives name -> engine constant -> name", lost.is_empty(), lost)

	# --- every setting has a control -------------------------------------
	# The one place this mapping is written down, on purpose: a new key in
	# DEFAULTS with no row here fails, which is the point.
	var controls := {
		"volume_master": "mastervolume",   "volume_music": "musicvolume",
		"volume_sfx": "sfxvolume",         "fullscreen": "fullscreentoggle",
		"vsync": "vsyncmode",              "frame_cap": "framecap",
		"window_width": "windowsize",      "window_height": "windowsize",
		"damage_numbers": "damagenumbers",
		"render_resolution": "renderresolution", "lighting": "lighting",
		"background_fps_limit": "backgroundlimit",
		# BOTH OF THESE WERE MISSING FROM THE TABLE, not from the game.
		# optionsscreen.gd wires the camera zoom slider and the name hue
		# slider, and the scene carries both controls with their swatch and
		# preview - the table simply was not updated when they were added, so
		# the check has been reporting two false positives ever since.
		#
		# WHICH IS THE FAILURE MODE OF A HAND-MAINTAINED MAPPING, and worth
		# naming: a check that cries wolf gets ignored, and then stops being a
		# check at all. Adding the two rows is the fix; the check itself is
		# still the right one, because a setting with no control is a real bug
		# and this is the only place that relationship is written down.
		"camera_zoom": "camerazoom",       "name_hue": "namehue",
	}
	var unmapped: Array = []
	for key in Settings.DEFAULTS:
		if not controls.has(key):
			unmapped.append(key)
	check("every setting in DEFAULTS is mapped to a control here", unmapped.is_empty(), unmapped)

	var packed: PackedScene = load("res://scene/ui/menus/optionsscreen.tscn")
	check("the options scene loads", packed != null)
	if packed == null:
		return
	var screen: Node = packed.instantiate()
	var missing: Array = []
	for key in controls:
		if screen.get_node_or_null("%" + controls[key]) == null:
			missing.append(controls[key])
	check("and every mapped control exists in it", missing.is_empty(), missing)
	check("including the readout the whole pacing section is for",
		screen.get_node_or_null("%pacingreadout") != null)
	check("and the renderer picker, which lives outside DEFAULTS",
		screen.get_node_or_null("%renderer") != null and screen.get_node_or_null("%renderernote") != null)
	screen.free()

	# --- performance: the defaults are the game as authored ---------------
	# Every performance option trades looks for speed, so none of them may be
	# ON by default except the one that costs nothing you can see.
	check("full resolution by default", Settings.DEFAULTS["render_resolution"] == "screen")
	check("full lighting by default", Settings.DEFAULTS["lighting"] == "full")
	check("the background limit is on by default - nobody sees those frames",
		Settings.DEFAULTS["background_fps_limit"] == true)
	check("30 is offered, for the weakest machines", 30 in Settings.FRAME_CAPS)

	check("an unknown resolution becomes the default",
		Settings.normalise_choice("potato", Settings.RENDER_RESOLUTIONS, "screen") == "screen")
	check("case does not matter to lighting",
		Settings.normalise_choice("Simple", Settings.LIGHTING_MODES, "full") == "simple")
	check("low resolution is viewport stretch",
		Settings.content_scale_mode_for("low") == Window.CONTENT_SCALE_MODE_VIEWPORT)
	check("screen resolution is the project's canvas_items",
		Settings.content_scale_mode_for("screen") == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)

	# --- the background limit, as a table ------------------------------------
	# (player's cap, focused, limit on) -> max_fps
	var caps := [
		[0, true, true, 0],     # foreground: the player's cap, which is none
		[144, true, true, 144],
		[0, false, true, Settings.BACKGROUND_FPS],
		[144, false, true, Settings.BACKGROUND_FPS],
		[10, false, true, 10],   # a lower cap is never RAISED by alt-tabbing
		[0, false, false, 0],    # limit off: background is the foreground
	]
	var wrong: Array = []
	for row in caps:
		if Settings.fps_cap_for(row[0], row[1], row[2]) != row[3]:
			wrong.append(row)
	check("the frame cap in and out of focus", wrong.is_empty(), wrong)

	# --- simple lighting on real nodes -------------------------------------
	# Hidden rather than disabled, because player.gd owns its carried light's
	# `enabled`; restored to exactly what was authored, including a light the
	# scene had hidden on purpose.
	var holder := Node2D.new()
	var lit := PointLight2D.new()
	var authored_off := PointLight2D.new()
	authored_off.visible = false
	var ambience := CanvasModulate.new()
	ambience.color = Color(0.28, 0.3, 0.4)
	for n in [lit, authored_off, ambience]:
		holder.add_child(n)
	for n in [lit, authored_off, ambience]:
		Settings._apply_lighting_to(n, "simple")
	check("simple hides a light", not lit.visible)
	check("and leaves `enabled` to player.gd", lit.enabled)
	check("and lifts the darkness", ambience.color.v > 0.4 and ambience.color.v < 1.0, ambience.color)
	for n in [lit, authored_off, ambience]:
		Settings._apply_lighting_to(n, "full")
	check("full brings the light back", lit.visible)
	check("but not one the scene hid itself", not authored_off.visible)
	check("and the darkness exactly as authored", ambience.color.is_equal_approx(Color(0.28, 0.3, 0.4)), ambience.color)
	holder.free()

	# --- the renderer note says which of three things is true -----------------
	var note := func(req: String, boot: String, run: String) -> String:
		return (load("res://src/ui/menus/optionsscreen.gd") as Script).renderer_note_for(req, boot, run)
	check("a pending switch asks for a restart",
		note.call("gl_compatibility", "mobile", "mobile").begins_with("restart"))
	check("a fallback says so", note.call("mobile", "mobile", "gl_compatibility").contains("no Vulkan"))
	check("otherwise it names what is running", note.call("mobile", "mobile", "mobile") == "running Standard")
	check("Forward+ is never offered - the heaviest renderer, for 3D",
		not ("forward_plus" in Settings.RENDERERS))


# =============================================================================
# MAP LANDMARKS - every placed landmark says what it is, and the map can draw it
# =============================================================================
# A pin comes from the thing it marks: mapscreen.gd draws whatever is in the
# "map_landmarks" group and asks each one map_landmark(). So the failure worth
# guarding is silent - a landmark that forgot to join, or reports a kind the
# map has no style for, simply has no pin, which looks exactly like a
# landmark that was never placed.

func _test_map_landmarks() -> void:
	section("MAP LANDMARKS")

	var style: Dictionary = (load("res://src/ui/menus/mapscreen.gd") as Script) \
		.get_script_constant_map().get("LANDMARK_STYLE", {})
	check("the map has a style table", not style.is_empty())
	var missing_art: Array = []
	for kind in style:
		var art: String = style[kind][0]
		if art != "" and not ResourceLoader.exists(art):
			missing_art.append(art)
	check("every pin icon the map names exists", missing_art.is_empty(), missing_art)

	# WHAT EACH AREA WILL ACTUALLY SHOW - the three world scenes, loaded the way
	# the game loads them, instantiated and NOT added to the tree: _init runs on
	# every node, which is where the group is joined, and _ready runs on none.
	#
	# BY AREA, NOT BY SCENE FILE, and the first draft of this section learned
	# why. It checked ladderup.tscn on its own and found no pin - because that
	# file has no script. It is a sprite and a collider, and a scene makes it a
	# ladder by attaching ladder.gd to its placed copy. The file is not what the
	# player sees; the area is.
	#
	# AT LEAST, not exactly: a second bank should not fail the suite. The exact
	# numbers are the two zeroes, below.
	var areas := {
		"res://scene/elusion.tscn":   ["shop", "bank", "cooking", "fishing", "teleport", "exit"],
		"res://scene/field.tscn":     ["ladder"],
		"res://scene/bossarena.tscn": ["boss"],
	}
	var pins_by_area := {}
	for path in areas:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			check("%s loads" % path.get_file(), false)
			continue
		var inst: Node = packed.instantiate()
		var found: Array = []
		_collect_landmark_nodes(inst, found)
		var counts := {}
		var colours := {}
		for n in found:
			var info: Dictionary = n.map_landmark()
			if info.is_empty():
				continue
			var kind: String = str(info.get("kind", ""))
			counts[kind] = int(counts.get(kind, 0)) + 1
			if kind == "boss":
				colours[info.get("colour", Color.BLACK)] = true
		pins_by_area[path.get_file()] = counts
		for kind in areas[path]:
			var article := "an" if "aeiou".contains(kind.left(1)) else "a"
			check("%s shows %s %s pin" % [path.get_file(), article, kind], int(counts.get(kind, 0)) >= 1, counts)
		var unknown: Array = counts.keys().filter(func(k): return not style.has(k))
		check("%s has no pin the map cannot draw" % path.get_file(), unknown.is_empty(), unknown)
		if int(counts.get("boss", 0)) > 1:
			# Six diamonds in one room are six identical diamonds otherwise.
			check("every boss gate there is its own colour",
				colours.size() == int(counts["boss"]), "%d gates, %d colours" % [counts["boss"], colours.size()])
		inst.free()

	# THE FIRST ZERO. The field's arrival portal runs leavetown.gd like the
	# town's real exit does, but it is one-way and vanishes after first use - so
	# the field must show no exit pin at all, or it advertises a way back to
	# town that does not exist.
	if pins_by_area.has("field.tscn"):
		check("the field shows NO exit pin - its portal is arrival-only",
			int(pins_by_area["field.tscn"].get("exit", 0)) == 0, pins_by_area["field.tscn"])

	# THE SECOND ZERO, and the one that keeps the gauntlet a gauntlet. The arena
	# used to hold a ladder back up to the field, which meant a player could walk
	# in, look at wave one, and walk out - and it made the victory teleporter
	# ceremonial, since there was already a way home before anything had been
	# beaten. The arena now has exactly one exit and you have to earn it. A
	# ladder reappearing here is the regression this catches, and it would be an
	# easy one to make by dragging ladderup.tscn back in without noticing what
	# it undoes.
	if pins_by_area.has("bossarena.tscn"):
		check("the boss arena shows NO ladder pin - the only way out is winning",
			int(pins_by_area["bossarena.tscn"].get("ladder", 0)) == 0, pins_by_area["bossarena.tscn"])

	# The same rule on a bare exit, so a failure above can be told apart: the
	# scene wiring changed, or leavetown.gd stopped honouring arrival_only.
	var exit_node: Node = (load("res://src/world/leavetown.gd") as Script).new()
	check("an exit is a landmark", exit_node.is_in_group("map_landmarks"))
	check("an ordinary exit has a pin", str(exit_node.map_landmark().get("kind", "")) == "exit")
	exit_node.arrival_only = true
	check("an arrival-only portal has none", exit_node.map_landmark().is_empty(), exit_node.map_landmark())
	exit_node.free()


# =============================================================================
# THE BOSS ARENA HAS ONE WAY IN AND ONE WAY OUT
# =============================================================================
# The arena used to have two exits: a ladder back up to the field, usable from
# the moment you arrived, and the victory teleporter that appears when the last
# boss falls. The ladder is gone, which makes the teleporter the only way home
# and the gauntlet a thing you finish.
#
# That is a better room and a more fragile one. With two exits, either could be
# broken and the player still got out. With one, a teleporter that never appears
# is a player stuck in a room with nothing left to kill, and the only way out is
# closing the game. So the wiring that used to be a convenience is now the
# contract, and these are the checks that hold it:
#
#   - the way IN still lands somewhere. The field's ladder down names a spawn
#     id; the arena must still have a marker carrying it. Deleting the ladder up
#     would have been an easy way to take the arrival marker with it, since they
#     sat next to each other in the same node.
#   - the way OUT exists, starts shut, and leads to a scene that is really there.
#   - there is something to clear. The teleporter only ever appears in answer to
#     gauntlet_cleared, so an arena with no gates is an arena with no exit.
#
# Instantiated, not added to the tree: _init runs, _ready does not. That is why
# nothing below looks for a group - fieldportal.gd joins "fieldportals" in
# _ready, so at this point it has not.

func _test_boss_arena_exits() -> void:
	section("BOSS ARENA - ONE WAY IN, ONE WAY OUT")

	var arena_packed: PackedScene = load("res://scene/bossarena.tscn") as PackedScene
	var field_packed: PackedScene = load("res://scene/field.tscn") as PackedScene
	check("the boss arena loads", arena_packed != null)
	check("the field loads", field_packed != null)
	if arena_packed == null or field_packed == null:
		return

	var arena: Node = arena_packed.instantiate()
	var field: Node = field_packed.instantiate()

	var ladder_script: String = "res://src/world/ladder.gd"

	# THE WAY OUT IS THE ONLY WAY OUT.
	var arena_ladders: Array = []
	_collect_by_script(arena, ladder_script, arena_ladders)
	check("the arena has no ladder - you leave by winning",
		arena_ladders.is_empty(), "%d found" % arena_ladders.size())

	# THE WAY IN STILL LANDS. The field's ladder down names the spot; the arena
	# has to still own a marker by that name.
	var field_ladders: Array = []
	_collect_by_script(field, ladder_script, field_ladders)
	var wanted: String = ""
	for node in field_ladders:
		if str(node.destination_scene_path) == "res://scene/bossarena.tscn":
			wanted = str(node.target_spawn_id)
	check("the field has a ladder down to the arena", wanted != "", wanted)

	var portal_ids: Array = []
	_collect_portal_ids(arena, portal_ids)
	check("the arena still has the arrival marker that ladder aims at",
		wanted != "" and portal_ids.has(wanted), "wants '%s', arena has %s" % [wanted, portal_ids])

	# THE WAY OUT EXISTS, IS SHUT, AND GOES SOMEWHERE.
	var teleporters: Array = []
	_collect_by_script(arena, "res://src/world/victoryteleporter.gd", teleporters)
	check("the arena has exactly one victory teleporter",
		teleporters.size() == 1, "%d found" % teleporters.size())

	if teleporters.size() == 1:
		var way_home: Node = teleporters[0]
		check("it starts hidden", not way_home.visible)
		check("it starts unsteppable", not way_home.monitoring)
		var shape: Node = way_home.get_node_or_null("collisionshape2d")
		check("its collider starts disabled", shape != null and shape.disabled)
		var home: String = str(way_home.destination_scene_path)
		check("it leads to a scene that exists",
			home != "" and ResourceLoader.exists(home), home)

	# SOMETHING TO CLEAR. No gates, no gauntlet_cleared, no teleporter, no exit.
	var gates: Array = []
	_collect_by_script(arena, "res://src/world/bossgate.gd", gates)
	check("there is a gauntlet to finish", gates.size() >= 1, "%d gates" % gates.size())
	check("the arena has a sequencer to run it",
		_has_script_in_tree(arena, "res://src/world/bossgauntlet.gd"))

	arena.free()
	field.free()


func _collect_by_script(node: Node, script_path: String, into: Array) -> void:
	var s: Script = node.get_script() as Script
	if s != null and s.resource_path == script_path:
		into.append(node)
	for child in node.get_children():
		_collect_by_script(child, script_path, into)


func _has_script_in_tree(node: Node, script_path: String) -> bool:
	var found: Array = []
	_collect_by_script(node, script_path, found)
	return not found.is_empty()


func _collect_portal_ids(node: Node, into: Array) -> void:
	# By the property, not the group: fieldportal.gd joins "fieldportals" in
	# _ready, and nothing here is in the tree for a _ready to run.
	if "portal_id" in node and str(node.portal_id) != "":
		into.append(str(node.portal_id))
	for child in node.get_children():
		_collect_portal_ids(child, into)


# =============================================================================
# STAFF PANEL - what it offers each rank, and how a kick reaches a player
# =============================================================================
# The server decides every one of these; the panel only declines to offer what
# would be refused. So the failure worth guarding is the panel drifting from
# app.py - offering a mod a permanent ban, or hiding a demotion the owner is
# allowed - which looks like a broken button either way. The rules are pure
# static functions on staffpanel.gd precisely so they can be pinned here
# without a server. The live run - real panel, real app.py, every button
# pressed - is in the commit that added this.

func _test_staff_panel() -> void:
	section("STAFF PANEL")

	var panel_script: Script = require_script(
		"res://src/ui/staff/staffpanel.gd", "the staff panel")
	if panel_script == null:
		return
	var offer := func(viewer: String, role: String, actionable: bool, banned: bool = false) -> Dictionary:
		return panel_script.actions_for(viewer, {"role": role, "actionable": actionable, "banned": banned})

	# ---- reach: can_act_on() is STRICTLY above ----
	var o: Dictionary = offer.call("mod", "player", true)
	check("a mod may kick and ban a player", o.kick and o.ban, o)
	check("but not permanently - MAX_MOD_BAN_DAYS", not o.ban_permanent, o)
	check("and changes no ranks", o.promote_to == "" and o.demote_to == "", o)
	check("unban is only offered on a ban", not o.unban and offer.call("mod", "player", true, true).unban)

	o = offer.call("mod", "mod", false)
	check("a mod cannot touch another mod", not o.kick and not o.ban and not o.unban, o)

	# BOTH SIDES MUST AGREE. The server's `actionable` is the authority, and
	# the client's own rank stops a panel that has not caught up with a
	# demotion from showing buttons its user just lost.
	check("a stale 'actionable' from the server offers nothing to an equal",
		not offer.call("mod", "mod", true).kick)
	check("and a client that thinks it outranks, against the server's no, offers nothing",
		not offer.call("owner", "player", false).kick)

	# ---- promotion: never to your own rank, never to owner ----
	o = offer.call("dev", "player", true)
	check("a dev may promote a player to mod", o.promote_to == "mod", o)
	check("and ban permanently", o.ban_permanent, o)
	o = offer.call("dev", "mod", true)
	check("a dev may not promote a mod - that would make a dev", o.promote_to == "", o)
	check("a dev may demote a mod to player", o.demote_to == "player", o)
	o = offer.call("owner", "mod", true)
	check("the owner may make a mod a dev", o.promote_to == "dev", o)
	o = offer.call("owner", "dev", true)
	check("owner is never offered as a promotion", o.promote_to == "", o)
	check("the owner may demote a dev to mod", o.demote_to == "mod", o)
	check("nobody is offered anything against the owner",
		not offer.call("owner", "owner", false).kick and not offer.call("dev", "owner", false).kick)

	# FAILS LOW, like Api.role_at_least(): a rank this build has never heard of
	# is a player, on either side.
	check("an unknown viewer rank is offered nothing", not offer.call("superuser", "player", true).kick)
	check("an unknown target rank reads as a player", offer.call("mod", "wizard", true).kick)

	# ---- the list ----
	var accounts: Array = [
		{"username": "zed", "online": false}, {"username": "Amy", "online": false},
		{"username": "bob", "online": true}, {"username": "al", "online": true},
	]
	var sorted: Array = panel_script.sort_accounts(accounts)
	check("online first, then by name ignoring case",
		sorted.map(func(e): return e.username) == ["al", "bob", "Amy", "zed"],
		sorted.map(func(e): return e.username))
	check("sorting does not reorder the caller's array", accounts[0].username == "zed")
	check("search ignores case",
		panel_script.filter_accounts(accounts, "AM", false).map(func(e): return e.username) == ["Amy"])
	check("online only",
		panel_script.filter_accounts(accounts, "", true).size() == 2)

	# ---- presence text, against the SERVER'S clock ----
	var now := 1_000_000
	check("online reads as online", panel_script.describe_presence({"online": true}, now) == "Online now")
	check("minutes", panel_script.describe_presence({"last_seen_at": now - 300}, now) == "Last seen 5 min ago",
		panel_script.describe_presence({"last_seen_at": now - 300}, now))
	check("hours", panel_script.describe_presence({"last_seen_at": now - 7200}, now) == "Last seen 2 h ago")
	check("days", panel_script.describe_presence({"last_seen_at": now - 3 * 86400}, now) == "Last seen 3 days ago")
	check("no heartbeat at all is just offline", panel_script.describe_presence({"last_seen_at": 0}, now) == "Offline")

	# ---- the scene carries every node the script reaches for ----
	var scene: Node = (load("res://scene/ui/staff/staffpanel.tscn") as PackedScene).instantiate()
	var missing: Array = []
	for unique in ["staffclosebutton", "staffyoulabel", "staffsearch", "staffonlineonly",
			"staffaccountlist", "staffemptylabel", "staffcountlabel", "staffpickhint",
			"staffdetail", "staffnamelabel", "staffpresencelabel", "staffranklabel",
			"staffbanlabel", "staffreachlabel", "staffreason", "staffkickbutton",
			"staffbanrow", "staffpermanentbutton", "staffunbanbutton", "staffrankrow",
			"staffpromotebutton", "staffdemotebutton", "staffnotice", "staffrefreshbutton"]:
		if scene.get_node_or_null("%" + unique) == null:
			missing.append(unique)
	check("staffpanel.tscn has every node staffpanel.gd uses", missing.is_empty(), missing)
	scene.free()

	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	# BY UNIQUE NAME, NOT BY PATH. This read "navhbox/staffrow/staffbutton" until
	# the nav row was wrapped in navframe to give it a frame. A hard-coded path
	# survives no rearrangement at all, and when it breaks it fails HERE, saying
	# the scene has lost its Staff button, when the button is sitting exactly
	# where it was and only the path to it moved. The unique name is resolved
	# against the scene, so wrapping the row again costs nothing.
	var staff_button: Node = hud.get_node_or_null("%staffbutton")
	check("the HUD has a Staff button on a row of its own", staff_button is Button)
	# HIDDEN IN THE FILE. The script shows it to staff; a player must never see
	# it even for the frame before the script runs.
	check("and it starts hidden", staff_button is Button and not (staff_button as Button).visible)

	# ---- the menu bar: the two lookups characterhud.gd makes by name ----
	# unique_name_in_owner is one checkbox in the inspector, and turning it off
	# costs nothing visible: the scene still opens, the buttons still draw, and
	# _wire_nav_buttons() quietly connects NOTHING, so every button in the menu
	# does nothing when clicked. That is the failure this pair of lines catches.
	var nav_row: Node = hud.get_node_or_null("%navbuttons")
	check("the HUD registers %navbuttons", nav_row != null)
	check("the HUD registers %staffrow", hud.get_node_or_null("%staffrow") != null)

	# AND THE BUTTONS THEMSELVES. _wire_nav_buttons() connects by name and skips
	# anything it cannot find, so a renamed button is a dead button with no error.
	var absent: Array = []
	for wanted in ["inventorybutton", "equipmentbutton", "statsbutton", "shopbutton",
			"kingdombutton", "tradebutton", "chatbutton", "friendsbutton",
			"guildbutton", "mapbutton", "optionsbutton", "logoutbutton",
			"switchcharacterbutton"]:
		if nav_row == null or nav_row.get_node_or_null(wanted) == null:
			absent.append(wanted)
	check("every button characterhud.gd wires up is in the scene", absent.is_empty(), absent)

	# ---- where the bar sits, checked against the things it has to miss ----
	var frame: Control = hud.get_node_or_null("%navframe") as Control
	check("the nav bar is framed", frame is PanelContainer)
	check("it hangs off the bottom of the screen",
		frame != null and frame.anchor_bottom == 1.0 and frame.offset_bottom < 0.0)
	# GROWING UPWARD IS THE POINT. The owner gets a second row; with the bottom
	# edge pinned, that row is added ABOVE and the ordinary menu stays put. Flip
	# this to END and the whole menu jumps whenever the owner signs in.
	check("and grows upward, so the menu sits in one place for everyone",
		frame != null and frame.grow_vertical == Control.GROW_DIRECTION_BEGIN)

	# THE RIGHT EDGE IS DODGING THE READOUTS, not a number picked by eye. The
	# health and magic bars run from barcontainer's offset plus their own, down
	# to y=709 - straight through the height of the menu bar. Both numbers are
	# read out of the scene here so that moving either one fails this line
	# instead of silently putting Logout underneath the health bar.
	var screen_w: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1280))
	var holder: Control = hud.get_node_or_null("barcontainer") as Control
	var hp: Control = hud.get_node_or_null("barcontainer/healthbar") as Control
	if frame != null and holder != null and hp != null:
		var bar_right: float = screen_w + frame.offset_right
		var readouts_left: float = holder.offset_left + hp.offset_left
		check("and it stops clear of the health and magic bars", bar_right < readouts_left,
			"bar ends at %.0f, the readouts begin at %.0f" % [bar_right, readouts_left])
	else:
		check("and it stops clear of the health and magic bars", false, "nodes missing")
	hud.free()

	# ---- the two social panels carry what their scripts reach for ----
	# Same failure as the HUD's own unique names, and the same silence: every
	# lookup in these two is get_node_or_null, so a missing name is a panel
	# that opens, draws, and does nothing at all when clicked.
	for spec in [
		["res://scene/ui/chat/chatpanel.tscn",
			["chatlines", "chatscroll", "chattabs", "chatentry", "chatsendbutton",
			"chatimagebutton", "chatclosebutton", "chatnotice", "chatto", "chattolabel"]],
		["res://scene/ui/friends/friendspanel.tscn",
			["friendsrows", "friendsaddentry", "friendsaddbutton", "friendsclosebutton",
			"friendsrefreshbutton", "friendsnotice", "friendscount"]],
		["res://scene/ui/equipment/equipmentpanel.tscn",
			["equipclosebutton", "equipdamagevalue", "equipspeedvalue", "equiparmourvalue",
			"equipsoakvalue", "equippreview", "equippreviewbox", "equippreviewhint"]],
		["res://scene/ui/guild/guildpanel.tscn",
			["guildrows", "guildtitle", "guildcount", "guildentry",
			"guildactionbutton", "actionpanel", "guildclosebutton",
			"guildrefreshbutton", "guildnotice", "footerbox",
			"guildleavebutton", "guilddisbandbutton"]],
	]:
		var built: Node = (load(String(spec[0])) as PackedScene).instantiate()
		var gone: Array = []
		for unique in spec[1]:
			if built.get_node_or_null("%" + String(unique)) == null:
				gone.append(unique)
		check("%s has every node its script uses" % String(spec[0]).get_file(),
			gone.is_empty(), gone)
		built.free()

	# ---- world chat cannot be used to paint the log ----
	# The log renders BBCode so staff ranks can be coloured, and BBCode is not
	# only colour: [img]url[/img] makes the client FETCH that url. A message is
	# text, so every opening bracket in one has to stop being a tag.
	var chat: Node = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	check("a bracket in a message is neutralised",
		chat._escape("[color=red]hi[/color]") == "[lb]color=red]hi[lb]/color]",
		chat._escape("[color=red]hi[/color]"))
	check("and so is an image tag",
		not chat._escape("[img]http://x/y.png[/img]").begins_with("[img"))
	check("ordinary text is left alone", chat._escape("hello there") == "hello there")

	# ---- four channels, and the client agrees with the server about them ----
	check("the client knows four channels", chat.CHANNELS.size() == 4, chat.CHANNELS)
	var unlabelled: Array = []
	for room in chat.CHANNELS:
		if not chat.CHANNEL_LABELS.has(room):
			unlabelled.append(room)
	check("and every one has a tab label", unlabelled.is_empty(), unlabelled)
	check("world is among them", chat.CHANNELS.has("world"))
	check("so is a private one", chat.CHANNELS.has("private"))
	check("and guild is declared, ready for when guilds are",
		chat.CHANNELS.has("guild"))

	# THE CAP THE BRIEF ASKED FOR, and it is PER CHANNEL. Shared, a busy world
	# channel would push a whisper out of its own window.
	check("a channel keeps 100 lines", chat.LINES_KEPT == 100, chat.LINES_KEPT)

	# ---- a picture is never loaded from the link somebody pasted ----
	# The whole reason the relay exists. If this file ever grows a call that
	# loads a remote URL directly, every viewer's address goes to whoever
	# posted it.
	var chat_source: String = FileAccess.get_file_as_string(
		"res://src/ui/chat/chatpanel.gd")
	check("the client asks the server to fetch pictures",
		chat_source.contains("/api/chat/image"))
	check("and decodes only what the server sent it",
		chat_source.contains("load_png_from_buffer"))
	check("nothing here opens a remote address itself",
		not chat_source.contains("http://") or chat_source.contains("begins_with(\"http://\")"))
	chat.free()

	# ---- the emoji font ships ----
	# A pasted emoji with no colour font behind it is a blank box, on every
	# machine, for everyone.
	check("the colour emoji font is in the project",
		ResourceLoader.exists("res://assets/fonts/NotoColorEmoji.ttf"))

	# ---- the hotbar ----
	# THE SLOTS MOVED TWO LEVELS DOWN when the bar was given a frame, and the
	# lookup that finds them used to be has_node("slot1") - a direct-child
	# check. That fails silently: nine warnings in the log, a hotbar that draws
	# perfectly and does nothing at all when you press a number key.
	var bar: Node = (load("res://scene/ui/hotbar.tscn") as PackedScene).instantiate()
	var lost: Array = []
	var keyless: Array = []
	for n in range(1, 10):
		var slot: Node = bar.find_child("slot%d" % n, true, false)
		if slot == null:
			lost.append("slot%d" % n)
			continue
		# AND THE KEY NUMBER IS A NODE NOW, not baked into the empty art - so
		# it is still there once a slot has something in it. That was the whole
		# complaint: a filled slot used to stop saying which key it was.
		var key: Label = slot.get_node_or_null("keylabel") as Label
		if key == null or key.text != str(n):
			keyless.append("slot%d" % n)
	check("every hotbar slot is findable", lost.is_empty(), lost)
	check("and each one shows its own key number", keyless.is_empty(), keyless)
	check("the bar itself is a framed panel", bar is PanelContainer, bar.get_class())

	# ---- the commissioned slot art is the slot ----
	# It used to be a 32px picture sitting INSIDE a panel the theme drew, which
	# meant an item icon covered it completely and the art you paid for was
	# only ever visible on an empty slot. As a nine-patched stylebox it frames
	# every slot, full or empty, and the item sits inside it.
	check("the slot art ships with the game",
		ResourceLoader.exists("res://art/images/hotbarslot.png"))
	var one: Control = bar.find_child("slot1", true, false) as Control
	var skin: StyleBox = one.get_theme_stylebox("panel") if one != null else null
	check("and it is what draws a slot", skin is StyleBoxTexture, skin)
	if skin is StyleBoxTexture:
		var skinned: StyleBoxTexture = skin as StyleBoxTexture
		# NINE-PATCHED. Without margins the frame stretches with the slot and
		# the artist's 1px outline turns into a smear.
		check("nine-patched, so the frame never stretches",
			skinned.texture_margin_left > 0.0 and skinned.texture_margin_top > 0.0,
			skinned.texture_margin_left)
		check("with the content pushed inside the frame",
			skinned.content_margin_left >= skinned.texture_margin_left,
			skinned.content_margin_left)
	# AND THE SLOT IS BIG ENOUGH TO HOLD SOMETHING. The art's hole is 18px at
	# its native 32; a 32px item icon in that is an icon wearing the frame as a
	# belt. See SLOT_SIZE in hotbarslot.gd.
	check("a slot is large enough for an item inside its frame",
		one != null and one.custom_minimum_size.x >= 40.0,
		one.custom_minimum_size if one else "no slot")
	bar.free()

	# ---- one statement of what a rank looks like ----
	# The nameplate over a player's head, their name in chat and their row in
	# the friends list all paint from this. Three copies would drift.
	check("every rank has a colour", Api.RANK_COLOURS.size() == 4, Api.RANK_COLOURS.size())
	check("the owner's is not the player's",
		Api.colour_for_role("owner") != Api.colour_for_role("player"))
	check("a rank this build has never heard of paints as a player",
		Api.colour_for_role("archmage") == Api.colour_for_role("player"))
	check("the client can be told when its rank changes",
		Api.has_signal("identity_changed"))

	# ---- the stat bars' numbers are anchored, not hand-placed ----
	# EVERY ONE OF THESE WAS WRONG IN A DIFFERENT WAY. The six labels had five
	# geometries between them: one at a fixed offset_left of 86, three anchored
	# full-width but with offsets of 85 and -87 that go NEGATIVE on any bar
	# narrower than 172, and two correct. The bars carry FILL|EXPAND, so none of
	# those numbers survives the panel being any width but the one they were
	# placed at - which is how "52/100" ended up sitting right of centre and
	# "85/100" ended up clipped.
	var stats: Node = (load("res://scene/ui/statsscreen.tscn") as PackedScene).instantiate()
	var adrift: Array = []
	for bar_name in ["attack", "defense", "agility", "magic", "fishing", "cooking"]:
		var tag: Control = stats.get_node_or_null("%" + bar_name + "barlabel") as Control
		if tag == null:
			adrift.append(bar_name + ": missing")
			continue
		# Anchored across the whole bar with no horizontal offsets is the only
		# arrangement that is centred at EVERY width.
		if tag.anchor_left != 0.0 or tag.anchor_right != 1.0:
			adrift.append("%s: anchors %.2f..%.2f" % [bar_name, tag.anchor_left, tag.anchor_right])
		elif tag.offset_left != 0.0 or tag.offset_right != 0.0:
			adrift.append("%s: offsets %.0f/%.0f" % [bar_name, tag.offset_left, tag.offset_right])
		elif tag.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			adrift.append(bar_name + ": not centred")
	check("every stat bar's number is centred on its bar", adrift.is_empty(), adrift)

	# AND THE TWO SECTIONS LINE UP. The skills rows' name labels expanded while
	# the combat rows' held a fixed 90, so the two blocks' bars started at
	# different x down the same panel.
	var ragged: Array = []
	for row_name in ["attackrow", "defenserow", "agilityrow", "magicrow",
			"fishingrow", "cookingrow"]:
		# find_child rather than a path: these six sit at the bottom of two
		# different seven-deep branches, and writing those out would make this
		# check break every time the panel is re-nested.
		var found: Node = stats.find_child(row_name, true, false)
		if found == null:
			ragged.append(row_name + ": missing")
			continue
		var name_tag: Control = found.get_node_or_null("label") as Control
		if name_tag == null or name_tag.custom_minimum_size.x != 90.0:
			ragged.append(row_name)
	check("every stat row's name holds the same width", ragged.is_empty(), ragged)
	stats.free()

	# ---- the window actually fills the screen ----
	# THIS IS THE ONE THAT MADE FULLSCREEN LOOK BROKEN. With
	# scale_mode="integer" the canvas is only ever drawn at a WHOLE multiple,
	# and 1920x1080 is 1.5x of the project's 1280x720 - so fullscreen on the
	# most common monitor there is drew the game at 1x in the middle of the
	# display inside a thick black frame. "fractional" is what makes 1.5x a
	# real scale.
	check("the canvas scales fractionally, so 1.5x is a real size",
		str(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) == "fractional",
		ProjectSettings.get_setting("display/window/stretch/scale_mode", ""))
	# AND THE ASPECT IS PINNED. "keep" is what holds the viewport at exactly
	# 1280x720 game units whatever the window is, which is what every offset in
	# every .tscn in this project was placed against. "expand" would hand a
	# wider monitor a wider viewport, and every hand-placed HUD element would
	# land somewhere else.
	check("and the aspect is kept, so every .tscn offset still lands",
		str(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep",
		ProjectSettings.get_setting("display/window/stretch/aspect", ""))

	# EVERY OFFERED SIZE IS THE VIEWPORT'S OWN SHAPE. With the aspect kept, a
	# window of any other shape gets black bars - so a size in this list that
	# is not 16:9 is a size that cannot fill its own window.
	var base_w: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1280))
	var base_h: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_height", 720))
	var wrong_shape: Array = []
	for option in Settings.WINDOW_SIZES:
		if not is_equal_approx(float(option.x) / float(option.y), base_w / base_h):
			wrong_shape.append("%dx%d" % [option.x, option.y])
	check("every window size offered is the viewport's own shape",
		wrong_shape.is_empty(), wrong_shape)
	check("and 1920x1080 is among them now",
		Settings.WINDOW_SIZES.has(Vector2i(1920, 1080)), Settings.WINDOW_SIZES)

	# ---- the camera view setting ----
	check("the camera setting defaults to what the scenes were authored at",
		is_equal_approx(float(Settings.DEFAULTS["camera_zoom"]), 3.0),
		Settings.DEFAULTS.get("camera_zoom"))
	check("and 3.0 is the ceiling",
		is_equal_approx(Settings.CAMERA_ZOOM_MAX, 3.0), Settings.CAMERA_ZOOM_MAX)
	# A HAND-EDITED options.cfg MUST NOT BE ABLE TO BREAK THE VIEW.
	check("a silly number out of the file is clamped, not obeyed",
		is_equal_approx(float(Settings._normalise("camera_zoom", 40.0)),
			Settings.CAMERA_ZOOM_MAX),
		Settings._normalise("camera_zoom", 40.0))
	check("and so is one below the floor",
		is_equal_approx(float(Settings._normalise("camera_zoom", -5.0)),
			Settings.CAMERA_ZOOM_MIN))
	# THE FLOOR IS 2.0, not 1.0. At 1x a 64px character is 64 screen pixels
	# and the nameplate over their head is smaller than they are.
	check("the camera cannot go further out than 2x",
		is_equal_approx(Settings.CAMERA_ZOOM_MIN, 2.0), Settings.CAMERA_ZOOM_MIN)

	var probe := Camera2D.new()
	probe.zoom = Vector2(3.0, 3.0)
	# A LEGAL SETTING, WHICH 1.5 HAS NOT BEEN SINCE THE FLOOR WENT TO 2.0.
	# This asked for 1.5 and expected 1.5 back, so once the floor was raised the
	# clamp did its job, handed back 2.0, and the test called correct behaviour a
	# failure - two red lines that mean "the constant above me changed", which is
	# the check three lines up already saying it louder.
	#
	# 2.5 is inside the range AND different from the 3.0 the probe starts at, so
	# a write that never happens still fails this the way it always should have.
	const LEGAL_ZOOM := 2.5
	Settings._apply_camera_zoom_to(probe, LEGAL_ZOOM)
	check("the setting reaches a camera",
		is_equal_approx(probe.zoom.x, LEGAL_ZOOM), probe.zoom)
	check("on both axes", is_equal_approx(probe.zoom.y, LEGAL_ZOOM), probe.zoom)
	Settings._apply_camera_zoom_to(probe, 99.0)
	check("and cannot push one past the ceiling",
		is_equal_approx(probe.zoom.x, Settings.CAMERA_ZOOM_MAX), probe.zoom)
	probe.free()

	# ---- the options screen carries the control ----
	var opts: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	var no_control: Array = []
	for unique in ["camerazoom", "camerazoomvalue"]:
		if opts.get_node_or_null("%" + unique) == null:
			no_control.append(unique)
	check("the options screen has the camera slider", no_control.is_empty(), no_control)
	var no_colour: Array = []
	for unique in ["namehue", "namecolourswatch", "namecolourpreview"]:
		if opts.get_node_or_null("%" + unique) == null:
			no_colour.append(unique)
	check("and the name colour slider", no_colour.is_empty(), no_colour)
	var slider: Range = opts.get_node_or_null("%camerazoom") as Range
	check("whose range matches the setting's own",
		slider != null and is_equal_approx(slider.min_value, Settings.CAMERA_ZOOM_MIN)
			and is_equal_approx(slider.max_value, Settings.CAMERA_ZOOM_MAX),
		"%s..%s" % [slider.min_value if slider else "?", slider.max_value if slider else "?"])
	var hue_slider: Range = opts.get_node_or_null("%namehue") as Range
	check("whose range is the whole hue wheel",
		hue_slider != null and is_equal_approx(hue_slider.min_value, Settings.NAME_HUE_MIN)
			and is_equal_approx(hue_slider.max_value, Settings.NAME_HUE_MAX))
	opts.free()

	# ---- the name colour ----
	# EVERY POSITION ON THE SLIDER HAS TO BE READABLE. Saturation and value are
	# fixed for exactly that reason, so the check is that they really are fixed
	# and that the wheel wraps rather than clamping at its ends.
	var dull: Array = []
	var hue: float = 0.0
	while hue < 360.0:
		var painted: Color = Settings.name_colour(hue)
		if not is_equal_approx(painted.v, Settings.NAME_VALUE):
			dull.append("hue %d is value %.2f" % [int(hue), painted.v])
		elif not is_equal_approx(painted.s, Settings.NAME_SATURATION):
			dull.append("hue %d is saturation %.2f" % [int(hue), painted.s])
		hue += 15.0
	check("every hue comes out at the one readable saturation", dull.is_empty(), dull)
	check("the wheel wraps rather than stopping",
		is_equal_approx(float(Settings._normalise("name_hue", 400.0)), 40.0),
		Settings._normalise("name_hue", 400.0))
	check("and wraps backwards too",
		is_equal_approx(float(Settings._normalise("name_hue", -20.0)), 340.0),
		Settings._normalise("name_hue", -20.0))
	check("the default hue is near the parchment the names already were",
		Settings.name_colour(float(Settings.DEFAULTS["name_hue"])).r > 0.9,
		Settings.name_colour(float(Settings.DEFAULTS["name_hue"])))

	# ---- staff cannot paint themselves a rank ----
	# The one thing a nameplate says that has to be TRUE. player.gd decides
	# this; the rule is checked here because a second copy of it anywhere is a
	# second chance to get it wrong.
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	check("a player gets the colour they chose",
		body._nameplate_colour("player") == Settings.name_colour(),
		body._nameplate_colour("player"))
	check("and so does a rank this build has never heard of",
		body._nameplate_colour("") == Settings.name_colour())
	var spoofed: Array = []
	for staff_rank in ["mod", "dev", "owner"]:
		if body._nameplate_colour(staff_rank) != Api.colour_for_role(staff_rank):
			spoofed.append(staff_rank)
	check("but staff keep their rank colour whatever the slider says",
		spoofed.is_empty(), spoofed)

	# ---- and the plate sits on the head, not above it ----
	# ONE NUMBER FOR FOUR CLASSES WAS THE BUG. The warrior's head is at -17 and
	# the mage's at -41; a shared -42 floated the warrior's name 25px of empty
	# air clear of them, which at 3x zoom is 75 screen pixels.
	var heads: Dictionary = body.NAMEPLATE_HEAD_Y
	check("every class has a measured head height",
		heads.has("warrior") and heads.has("mage") and heads.has("healer")
			and heads.has("tank"), heads)
	var same: bool = (float(heads["warrior"]) == float(heads["mage"]))
	check("and they are not all the same number", not same, heads)

	# ---- the crown ----
	# ONE ACCOUNT WEARS IT. The rank it keys off is the server's, copied into
	# the chat row by app.py and read out of /api/friends - not the name colour
	# beside it, which is a local preference anybody can set to anything.
	var crown_file: String = body.NAMEPLATE_CROWN_PATH
	check("the crown art ships with the game", ResourceLoader.exists(crown_file),
		crown_file)
	var crown_art: Texture2D = load(crown_file) as Texture2D
	check("and loads as a texture", crown_art != null)
	check("at the size the chat tag and the plate both assume",
		crown_art != null and crown_art.get_width() == 26 and crown_art.get_height() == 15,
		crown_art.get_size() if crown_art else "none")
	check("only the owner wears it", body.NAMEPLATE_CROWN_RANK == "owner",
		body.NAMEPLATE_CROWN_RANK)

	# THE THREE PLACES THAT DRAW IT MUST AGREE. A path typed out three times is
	# three chances for one of them to point at nothing, and a missing [img] in
	# a RichTextLabel fails silently.
	var chat_src: String = FileAccess.get_file_as_string("res://src/ui/chat/chatpanel.gd")
	var mates_src: String = FileAccess.get_file_as_string("res://src/ui/friends/friendspanel.gd")
	check("world chat points at the same file", chat_src.contains(crown_file), crown_file)
	check("the friends list points at the same file", mates_src.contains(crown_file))
	check("and both agree on who wears it",
		chat_src.contains('"owner"') and mates_src.contains('"owner"'))

	# AND IT IS ACTUALLY DRAWN, not merely spelled correctly in a constant.
	# The two checks above passed for chat and failed for the friends list for
	# as long as the friends list had no crown at all - which is the right
	# answer, but only because the path happened to be absent too. A panel that
	# declared the constant and never used it would slip straight past them.
	check("and the friends list really puts it in a row",
		mates_src.contains("CROWN_RANK") and mates_src.contains("line.add_child(crown)"),
		"friendspanel.gd names the crown but never adds it to a row")
	body.free()

	# ---- the heartbeat: only a 401 signs anyone out ----
	check("a live session beats ok", Api.heartbeat_verdict({"ok": true, "status": 200}) == "ok")
	check("a 401 is a kick, a ban or an expiry", Api.heartbeat_verdict({"ok": false, "status": 401}) == "revoked")
	# A SERVER RESTART MUST NOT BE A MASS KICK.
	for status in [0, 404, 500, 503]:
		check("HTTP %d signs nobody out" % status,
			Api.heartbeat_verdict({"ok": false, "status": status}) == "offline")
	# Three beats inside app.py's ONLINE_WINDOW_SECONDS, which is 45. Written
	# out because the two numbers live in different repositories.
	check("three heartbeats fit inside the server's 45 s online window",
		Api.HEARTBEAT_SECONDS * 3.0 <= 45.0, Api.HEARTBEAT_SECONDS)

	# ---- what a banned player is told ----
	var login_script: Script = require_script(
		"res://src/ui/menus/loginmenu.gd", "the login menu")
	if login_script == null:
		return
	var told: String = login_script.describe_login_refusal({"status": 403,
		"data": {"message": "This account is banned.", "ban": {"permanent": true, "reason": "cheating"}}})
	check("a permanent ban says so, and why", told.contains("permanently") and told.contains("cheating"), told)
	told = login_script.describe_login_refusal({"status": 403,
		"data": {"ban": {"permanent": false, "expires_at": 1_900_000_000, "reason": ""}}})
	check("a timed ban gives its date", told.begins_with("This account is banned until 20"), told)
	told = login_script.describe_login_refusal({"status": 500, "error": "Server error."})
	check("anything else passes the error through", told == "Server error.", told)


func _collect_landmark_nodes(node: Node, into: Array) -> void:
	if node.is_in_group("map_landmarks") and node.has_method("map_landmark"):
		into.append(node)
	for child in node.get_children():
		_collect_landmark_nodes(child, into)


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
