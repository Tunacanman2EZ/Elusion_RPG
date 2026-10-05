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

# How a name is drawn in every list - checked directly, and through the panels
# that use it. Preloaded, like everywhere else; nametag.gd says why.
const NameTag := preload("res://src/shared/nametag.gd")
const ApiForTests := preload("res://src/systems/api.gd")
const PoolForTests := preload("res://src/systems/connectionpool.gd")


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
var skipped: int = 0
var skips: PackedStringArray = []
var _log: PackedStringArray = []

# A SCRIPT ERROR ENDS THE SECTION IT HAPPENS IN, AND SAID NOTHING ABOUT IT.
# The function stops at the bad line, its remaining checks never run, and a run
# with eight of them still printed "0 failed". It happened: a trade test still
# called _adopt_refusal() after that function was deleted, and every check after
# it in that section went quietly unrun through a whole batch whose summary read
# green. Godot 4.5's Logger hears every error the engine reports, and only a
# SCRIPT ERROR - not a push_error() a check provokes on purpose - counts here.
class ScriptErrorCounter extends Logger:
	var count: int = 0
	var where: PackedStringArray = []
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		count += 1
		if where.size() < 8:
			where.append("%s:%d  %s" % [file.get_file(), line, (rationale if rationale != "" else code).left(90)])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

var _script_errors: ScriptErrorCounter = null


# Started before the first section and read by _report(), so a SCRIPT ERROR
# anywhere in the run is a failed check rather than a missing one.
func _watch_script_errors() -> void:
	if _script_errors == null:
		_script_errors = ScriptErrorCounter.new()
		OS.add_logger(_script_errors)


func _check_no_script_errors() -> void:
	if _script_errors == null:
		return
	OS.remove_logger(_script_errors)
	section("SCRIPT ERRORS - none, anywhere in the run")
	check("the run raised no SCRIPT ERROR (one ends its section early, and the rest of that section never runs)",
		_script_errors.count == 0,
		"%d of them, first: %s" % [_script_errors.count, "; ".join(_script_errors.where)])
	_script_errors = null


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
	_watch_script_errors()
	await _run_all()
	_report()


func _run_all() -> void:
	# FIRST, DELIBERATELY. A script that will not compile makes unrelated sections
	# fail for reasons their own names do not mention. See the header above
	# _test_every_script_compiles() for the eight gold failures that came out of
	# one bad line in baseenemy.gd.
	_test_every_script_compiles()
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
	_test_script_references()
	_test_element_enum_order()
	_test_spawn_ordering()
	_test_await_does_not_lose_work()
	_test_helper_scripts_ascii()
	_test_art_folders_are_licensed()
	_test_third_party_licences()
	_test_audio_paths()
	_test_every_portal_makes_a_sound()
	_test_chat_picture_sweep()
	_test_chat_deletions_reach_the_client()
	_test_security_policy()
	_test_skills_are_not_pushed()
	_test_god_mode_earns_nothing()
	_test_teleport_is_wired()
	_test_players_menu_and_pvp_are_honest()
	_test_death_reaches_the_server()
	_test_world_status_is_shown()
	_test_timestamps_are_the_servers()
	_test_board_says_what_it_is_made_of()
	_test_the_guild_tag_is_drawn_everywhere()
	_test_panels_are_windows()
	_test_unauthorized_is_answered()
	_test_the_client_says_which_build_it_is()
	_test_login_states_are_distinct()
	_test_no_import_cache_references()
	_test_every_font_draws_without_the_os()
	_test_a_save_from_outside_the_tree()
	_test_no_unused_parameters()
	_test_floor_coverage()
	_test_frame_budget()
	_test_only_levelling_up_refills()
	_test_nothing_shadows_its_base_class()
	_test_every_resource_reference_exists()
	_test_panels_fill_their_window()
	_test_slots_wear_the_hotbar_socket()
	_test_the_bank_reads_well()
	_test_notices_fade_and_login_is_quiet()

	# LAST, AND AWAITED. This is the one section that needs the tree to tick - it
	# waits for a real animation to finish rather than calling the handler by
	# hand. An un-awaited coroutine would return here immediately and the rest of
	# its checks would run AFTER _report() had already printed the totals, which
	# is the "section that died halfway still reports 0 failed" trap wearing a
	# different hat. Hence `await _run_all()` in _ready() as well.
	await _test_the_shopkeeper_waves_once()
	await _test_props_block_the_player()
	await _test_a_lit_fire_opens_cooking()
	await _test_the_hotbar_holds_items()
	await _test_the_gm_panel_is_a_window()
	await _test_the_staff_desk()
	await _test_the_guild_panel_reads_well()
	await _test_trades_reach_the_right_people()
	await _test_guild_chat_is_open()
	await _test_the_staff_desk_reads_trades()
	await _test_the_friends_header_reads_well()
	await _test_the_world_loads_in_the_background()
	await _test_rare_loot_reads_as_rare()
	await _test_amulets_carry_their_bonus()
	await _test_the_game_has_a_pace()
	await _test_better_loot_carries_more()
	_test_bosses_hit_for_their_band()
	await _test_gear_bonuses_are_shown()
	await _test_tooltips_say_it_once()
	await _test_the_sweep_wiring()
	_test_the_sweep_words()
	_test_the_browser_build()
	_test_the_windows_build()
	await _test_leaving_waits_for_the_save()
	_test_skill_xp_rounds_like_the_server()
	await _test_game_keys_are_not_menu_keys()
	_test_staff_logins_take_a_code()
	_test_chat_is_one_line_per_message()
	await _test_chat_keeps_your_place()
	await _test_whispers_reach_you()
	_test_black_past_the_map()
	_test_signing_in_never_makes_an_account()
	_test_remember_me_means_it()
	_test_one_game_per_account()
	_test_email_prompt_can_wait()
	_test_chat_filter()
	_test_chat_safety_menu()
	_test_staff_reports_and_mutes()
	await _test_a_failed_load_is_not_an_empty_account()
	_test_character_select_has_a_way_out()
	await _test_every_area_can_be_walked()
	await _test_the_big_field()
	await _test_far_enemies_sleep()
	_test_the_welcome_plays_once_a_login()
	_test_a_character_can_be_deleted()
	_test_one_code_per_computer()
	_test_install_id_is_kept_and_sent()
	_test_a_window_never_outgrows_the_screen()
	await _test_banked_gold_goes_through_the_server()
	_test_the_store_sells_the_next_set()
	await _test_founding_a_guild_shows_what_it_cost()
	_test_a_request_waiting_on_you_lights_its_button()
	_test_the_login_screen_asks_without_a_login()
	_test_a_gateway_saying_no_answer_is_no_answer()
	_test_a_lost_server_is_asked_for_more_often()
	await _test_the_bag_is_the_servers()
	await _test_the_map_comes_back()
	_test_enemies_keep_their_place_in_the_ring()
	_test_a_door_is_quick()
	_test_the_emoji_font_is_chat_sized()
	await _test_connections_are_kept_open()
	_test_the_powers_panel_closes()
	_test_the_staff_windows_share_one_look()
	await _test_players_right_click_menu()
	_test_the_stats_window_reads_cleanly()
	await _test_bank_buttons_and_the_cooking_window()
	_test_the_tank_loop_takes_every_step()
	await _test_the_first_five_minutes()
	await _test_the_mythic_weapons()
	await _test_the_item_menu()
	await _test_mythic_drops()


# =============================================================================
# CONFIGURE BEFORE add_child(), or the profile multiplies nothing
# =============================================================================
# add_child() is what runs _ready(). bossprojectile.gd's _ready() calls
# _apply_element_profile(), and that function MULTIPLIES what the caller set:
#
#     telegraph_seconds = telegraph_seconds * p["telegraph"]
#     damage            = damage * p["damage"]
#     scale            *= p["size"]
#
# Set those AFTER add_child and two things happen, neither of them loud: the
# profile scaled the scene's defaults instead of your values, and your
# assignment then flattened the result. The thing spawns wearing its element's
# ART and none of its behaviour.
#
# THIS IS NOT HYPOTHETICAL. bossstalker._drop_pillar() did exactly that, and
# every pillar in a stalker's trail telegraphed in 0.50s and hit for 22 whether
# it was lightning or earth, while the boss's own cast pillars - spawned in the
# right order - varied 0.25s to 0.68s and 19 to 28. It was invisible because a
# flat number is not a wrong number, it is just not an elemental one.
#
# The same trap has a second face, recorded in bossenemy.gd: an assignment onto
# a property the scene does not have RAISES, and every statement below it in the
# function silently never runs. That is why the correct sites guard with
# `if "x" in node` before setting anything they do not own.
#
# So this reads the source of every spawn site and asserts the order. It is a
# text check on purpose - the failure it guards has no runtime symptom to assert
# against, which is the entire reason it survived as long as it did.

const READY_SENSITIVE_PROPS := [
	"element", "element_override", "damage", "telegraph_seconds", "is_small",
]


func _test_spawn_ordering() -> void:
	section("SPAWN ORDER — configure before add_child(), not after")

	var offenders: Array[String] = []
	var sites: int = 0
	for folder in ["res://src/enemies", "res://src/projectiles", "res://src/pets"]:
		_scan_spawn_order(folder, offenders, [sites])

	# Recount by scanning again into a local, since GDScript cannot pass an int
	# by reference and the array trick above only carries the offenders out.
	offenders.sort()
	check("nothing configures an element-bearing property after add_child()",
		offenders.is_empty(), "\n         ".join(offenders))

	print("  checked every add_child() in enemies, projectiles and pets")


func _scan_spawn_order(dir_path: String, offenders: Array[String], _n: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_spawn_order(full, offenders, _n)
		elif entry.ends_with(".gd"):
			var lines: PackedStringArray = FileAccess.get_file_as_string(full).split("\n")
			for i in range(lines.size()):
				var line: String = lines[i]
				var at: int = line.find("add_child(")
				if at < 0 or line.strip_edges().begins_with("#"):
					continue
				var from: int = at + 10
				var to: int = line.find(")", from)
				if to < 0:
					continue
				var subject: String = line.substr(from, to - from).strip_edges()
				if subject == "" or subject.contains("\"") or subject.contains("("):
					continue
				# Look ahead a few lines for a configure-after.
				for j in range(i + 1, mini(i + 12, lines.size())):
					var later: String = lines[j].strip_edges()
					if later.begins_with("#"):
						continue
					for prop in READY_SENSITIVE_PROPS:
						if later.begins_with("%s.%s = " % [subject, prop]) \
								or later.begins_with("%s.%s=" % [subject, prop]):
							offenders.append("%s:%d  add_child(%s) then %s.%s"
								% [full.get_file(), j + 1, subject, subject, prop])
		entry = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# EVERY SCRIPT STILL COMPILES
# =============================================================================
# This runs FIRST, and the reason is a cascade worth describing, because the
# cascade is what makes a broken build expensive to diagnose rather than just
# broken.
#
# A one-argument call to Combat.report_kill() - which takes three - was put into
# baseenemy.gd as a deliberate sabotage while proving the await check below.
# GDScript validates the arity at compile time, so BaseEnemy stopped compiling,
# so every check reading BaseEnemy.GOLD_* had no class to read from. The suite
# reported EIGHT failures, all of them named gold_something, and not one line
# naming baseenemy.gd. The honest state of the project was "one script does not
# compile"; the report said "the gold constants disagree with the contract".
#
# Anybody chasing that goes into the gold code, which is fine, and finds nothing
# wrong there, which is also fine, and that is the wasted hour.
#
# require_script() already solves this per-section and says so in its docstring.
# It is only used where a section does an explicit load(), and the sections that
# reach a global class name directly - BaseEnemy.X, ItemData.Y - get no such
# guard, because there is no load() call to put it on. This check covers them
# all at once instead: if something under src/ will not compile, the FIRST line
# of the report names the file, and everything red below it is downstream.
#
# It also folds in a fact that until now lived outside the suite entirely. "All
# scripts compile" was only ever proven by launching a separate scene by hand,
# which means it was not proven by run_tests.ps1, which is the thing a person
# who clones this repository actually runs, and the thing CI runs.
#
# HOW TO ASK, WHICH IS NOT OBVIOUS AND WAS GOT WRONG HERE FIRST.
#
# The first version of this check tested `load(path) as Script != null`. It
# passed on a project with a script that did not compile - green, 111 loaded,
# while eight gold checks were failing underneath it because the class it was
# green about did not exist. A check that passes in the exact condition it exists
# to catch is worse than no check, because it is evidence.
#
# So the probes were measured, on three separate ways of breaking one file (a
# wrong-arity call, a syntax error, and a type mismatch) against a good one:
#
#   probe                            good        all three broken
#   load()                           object      OBJECT  <- always non-null
#   load(CACHE_MODE_IGNORE)          object      OBJECT  <- also always non-null
#   can_instantiate()                true        false
#   reload()                         0 (OK)      43 (ERR_PARSE_ERROR)
#   get_script_constant_map().size() 1           0
#   get_script_method_list().size()  1           0
#
# load() never reports the failure. reload() reports it perfectly but RECOMPILES
# the script in place, which is not a thing to do to a live project from inside
# its own test suite. can_instantiate() is the read-only one that moves.
#
# Used with two corroborating conditions rather than alone, because
# can_instantiate() is also false for a legitimately abstract script - and a
# future abstract class failing this check would be a false alarm that teaches
# people to ignore it. A script that will not parse has no methods and no
# constants either; an abstract one that declares either is therefore left
# alone. All three together is the parse failure and nothing else.
#
# Loading is otherwise safe to do in bulk: it parses and compiles, it does not
# execute, and anything already in memory comes back from the resource cache.


func _test_every_script_compiles() -> void:
	section("COMPILE — every script under src/ parses")

	var broken: Array[String] = []
	var total: Array[int] = [0]
	_scan_compiles("res://src", broken, total)

	broken.sort()
	check("the sweep found scripts to check", total[0] > 0, "%d found" % total[0])
	check("every script under src/ compiles", broken.is_empty(),
		"\n         ".join(broken))

	print("  %d scripts parsed" % total[0])


func _scan_compiles(dir_path: String, broken: Array[String], total: Array[int]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_compiles(full, broken, total)
		elif entry.ends_with(".gd"):
			total[0] += 1
			# Errors off across the load, because a script that will not compile
			# prints its parse error to stderr and the point of this check is to
			# name the file in the summary, not to bury it in engine output.
			Engine.print_error_messages = false
			var script: Script = load(full) as Script
			Engine.print_error_messages = true
			if script == null:
				# Not observed on any of the three break kinds measured above,
				# but a genuinely unreadable file would land here.
				broken.append("%s did not load at all" % full)
			elif not script.can_instantiate() \
					and script.get_script_method_list().is_empty() \
					and script.get_script_constant_map().is_empty():
				broken.append("%s will not compile" % full)
		entry = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# WORK LOST PAST AN AWAIT
# =============================================================================
# Measured on 4.6.1, not assumed. A node suspended on
# `await get_tree().create_timer(...).timeout`:
#
#   queue_free()d, or its scene replaced  -> the coroutine NEVER RESUMES.
#                                            Nothing below the await runs. No
#                                            error, no warning, no output.
#   remove_child() without a free         -> resumes, valid, NOT inside tree.
#   reparented, still in the tree         -> resumes, nothing to guard.
#
# combat.gd's header holds the full table and the reasoning. What matters for a
# CHECK is the first row, and specifically that it is silent. A dropped
# coroutine and a completed one are indistinguishable in the log, so the only
# thing that ever notices is a player wondering where their loot went.
#
# THAT IS NOT HYPOTHETICAL EITHER. Small poison slimes await their death
# animation and larges do not, and for months smalls dropped no loot bag at all
# for exactly this reason. The fix was moving the work to an autoload, which is
# why combat.gd exists as one.
#
# WHAT THIS CHECKS, AND WHY IT IS NARROW. Losing a write to your own member is
# usually harmless - the node is going away and taking the member with it. What
# is never harmless is losing work aimed OUTSIDE yourself: a kill report, a
# signal someone is waiting on, a bag added to a container. So this fires only
# when code after an await in a self-freeing node reaches for one of those.
#
# Scoped to enemies, projectiles and pets because those are the nodes that free
# themselves mid-life. Autoloads are always in the tree and UI panels live as
# long as their scene, so the same pattern there is not the same risk.
const AWAIT_OUTSIDE_TOKENS := [
	"Combat.", "CharacterData.", "ServerStorage.", "Api.", "SkillTrainer.",
	"GameState.", "add_child(", "call_deferred(", ".emit(", "emit_signal(",
	"get_first_node_in_group(",
]


func _test_await_does_not_lose_work() -> void:
	section("PAST AN AWAIT — no outside-world work below an await that can be dropped")

	var offenders: Array[String] = []
	for folder in ["res://src/enemies", "res://src/projectiles", "res://src/pets"]:
		_scan_await_losses(folder, offenders)

	offenders.sort()
	check("nothing reaches outside itself after an await in a self-freeing node",
		offenders.is_empty(), "\n         ".join(offenders))

	print("  checked every await in enemies, projectiles and pets")


func _scan_await_losses(dir_path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_await_losses(full, offenders)
		elif entry.ends_with(".gd"):
			var lines: PackedStringArray = FileAccess.get_file_as_string(full).split("\n")
			for i in range(lines.size()):
				var line: String = lines[i]
				if not line.contains("await ") or line.strip_edges().begins_with("#"):
					continue
				# Walk to the end of the enclosing function: the first later line
				# that has content and does NOT start with a tab is the next
				# top-level declaration.
				for j in range(i + 1, lines.size()):
					var raw: String = lines[j]
					var body: String = raw.strip_edges()
					if body != "" and not raw.begins_with("\t"):
						break
					if body == "" or body.begins_with("#"):
						continue
					var flagged: bool = false
					for token in AWAIT_OUTSIDE_TOKENS:
						if body.contains(token):
							offenders.append("%s:%d  await on line %d, then %s"
								% [full.get_file(), j + 1, i + 1, body.left(56)])
							flagged = true
							break
					if flagged:
						break
		entry = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# EVERY ART FOLDER IS CLASSIFIED BY SOMEBODY
# =============================================================================
# This one is not about the game working. It is about the repository not claiming
# copyright it does not have, which has now gone wrong twice for the same reason.
#
# LICENSE used to say "all original artwork, music, and paid/commissioned assets
# in this repository are the exclusive property of Robert Ashley Clear", and when
# it was written that was TRUE - one artist, commissioned, rights assigned. It
# became false the day a purchased pack from a second artist arrived, and nothing
# went back to reread it. Adding art does not feel like touching licensing, so
# nobody does.
#
# Caught the same thing a second time while fixing the first: /art/thirdparty/
# held tilesets that split_art.ps1 itself describes as "of unconfirmed origin",
# and assetlicense.md's catch-all - everything under /art except the item art -
# was quietly claiming them. That folder is GONE now rather than disclosed: its
# one remaining file was used only by scene/walls/shop.tscn, which was the old
# shop, orphaned - nothing referenced it by path or by uid. Both were deleted, so
# the repository no longer ships art nobody can account for.
#
# A LICENCE FILE IS A CLAIM ABOUT A SET OF FILES, and the set changes without the
# claim changing. So the claim is pinned to names here, and a folder nobody has
# classified fails the suite until somebody decides whose it is. The next time art
# arrives from a new source, the thing that notices is a test run rather than a
# stranger reading the repository.
#
# DELIBERATELY A HARDCODED LIST, not derived from assetlicense.md by parsing it.
# A parser would keep passing while the prose rotted around it; the point is that
# a human has to type the folder name in two places and think once.
#
# WHAT THIS CHECK CANNOT SEE, stated plainly because it is the hole that let the
# third case through. This works at FOLDER granularity. It cannot express "these
# two files inside art/tiles belong to a different artist", and that is exactly
# what was found: two tiles from the purchased Clockwork Raven pack sitting in
# art/tiles/, a folder whose owner here is "elusion". Green the whole time.
#
# The pack is a general fantasy asset pack - it has tilesets in it, not only
# items and icons - so the old rule in assetlicense.md, which was about the
# CATEGORY of art, could not catch them either. Both files were unreferenced and
# are gone, so folder granularity is honest again today.
#
# The durable fix is not in this check, it is the rule assetlicense.md now states:
# art/pack/ is the authoritative location for anything of Caio's, so a file of
# his anywhere else is a split that was missed. If a future pack file has to live
# outside art/pack/, this check will not notice, and whoever puts it there owes
# this comment an update.
const LICENSED_ART_FOLDERS := {
	# Elusion Studios: commissioned from Ahvassa with rights assigned, plus
	# original work.
	"art/doors": "elusion",
	"art/enemy": "elusion",
	"art/floordecoration": "elusion",
	"art/images": "elusion",
	"art/maincharacter": "elusion",
	"art/menu": "elusion",
	"art/npc": "elusion",
	"art/shophouses": "elusion",
	"art/teleport": "elusion",
	"art/tiles": "elusion",
	"assets/themes": "elusion",
	"audio/ambience": "elusion",
	# Recorded by the owner (day 2: teleport, a Stylophone through a CPM DS-2).
	"audio/sfx": "elusion",

	# Google, SIL Open Font License 1.1 - NOT Elusion Studios', and not
	# Clockwork Raven's either. It held the folder's only file while the folder
	# was classified "elusion", which is the fourth time a claim in
	# assetlicense.md outlived the files it described.
	"assets/fonts": "google-ofl",

	# Caio Carlos / Clockwork Raven Studios, purchased under their asset licence.
	# Credit is REQUIRED, not courtesy. The private submodule lives here.
	"art/pack": "clockwork-raven",

	# NOTHING IS "unconfirmed" ANY MORE, and that is the point of leaving this
	# note where the entry used to be. art/thirdparty held one file of unknown
	# origin; it was reachable only from the orphaned old shop scene, so both went.
	# If a folder ever needs that classification again, it means art arrived from
	# a source nobody verified - which is a conversation, not a list entry.
}


func _test_art_folders_are_licensed() -> void:
	section("ART LICENSING — every art folder is classified by name")

	var unclassified: Array[String] = []
	var missing: Array[String] = []
	var found: Array[String] = []

	for root in ["res://art", "res://assets", "res://audio"]:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with("."):
				var key: String = "%s/%s" % [root.trim_prefix("res://"), entry]
				# EMPTY FOLDERS DO NOT COUNT, and this is not a convenience.
				#
				# Git cannot represent an empty directory. So a folder left behind
				# on one machine after its files moved elsewhere exists for that
				# developer and for nobody who clones - and a check that counted it
				# would FAIL on their machine and PASS in CI, on the same commit.
				# That is the one kind of failure that teaches people to ignore a
				# suite, so it is worth more than the handful of lines it costs.
				#
				# Found the honest way: split_art.ps1 moved the purchased art into
				# art/pack/ and left seven empty folders behind - amulets, armour,
				# consumables, currency, icons, lootbag, weapons. This check went
				# red on the author's machine and green in a clean clone.
				#
				# An empty folder is also not a licensing risk, which is the actual
				# subject. Nobody can misattribute art that is not there.
				if not _folder_holds_art(dir_path_of(root, entry)):
					entry = dir.get_next()
					continue
				found.append(key)
				if not LICENSED_ART_FOLDERS.has(key):
					unclassified.append("%s is not classified in assetlicense.md" % key)
			entry = dir.get_next()
		dir.list_dir_end()

	# Both directions. A folder that disappeared should be taken OUT of the list,
	# or the list slowly becomes a record of what used to be here - which is how
	# the prose it mirrors went stale in the first place.
	#
	# art/pack is exempt: it is the private submodule, so it is legitimately
	# absent from any clone without access to it, and failing every such clone
	# would train people to ignore this check.
	for key in LICENSED_ART_FOLDERS:
		if key == "art/pack":
			continue
		if not found.has(key):
			missing.append("%s is classified but no longer exists" % key)

	check("the sweep found art folders to check", not found.is_empty(),
		"%d found" % found.size())
	check("every art folder has a named owner", unclassified.is_empty(),
		"\n         ".join(unclassified))
	check("no classified folder has gone missing", missing.is_empty(),
		"\n         ".join(missing))

	print("  %d folders hold art; %d classified"
		% [found.size(), LICENSED_ART_FOLDERS.size()])


# Audio counts: audio/ is an asset root like the others, and was scanned by
# nothing until a font turned out to be misfiled and the same question got asked
# of every folder that holds something somebody owns.
const ART_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg", "ttf", "otf", "tres",
	"ogg", "wav", "mp3", "rpp"]


func dir_path_of(root: String, entry: String) -> String:
	return root.path_join(entry)


func _folder_holds_art(dir_path: String) -> bool:
	# Recursive: art/tiles/field/ counts toward art/tiles.
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	var holds: bool = false
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and _folder_holds_art(full):
				holds = true
		elif ART_EXTENSIONS.has(entry.get_extension().to_lower()):
			holds = true
		if holds:
			break
		entry = dir.get_next()
	dir.list_dir_end()
	return holds


# =============================================================================
# NO SCENE MAY POINT INTO THE IMPORT CACHE
# =============================================================================
# .godot/ is gitignored, so it exists on the machine that built it and in no
# clone, ever. A scene that names a file inside .godot/imported/ therefore works
# for exactly one person and is blank for everybody else - including that person,
# as soon as Godot cleans the cache.
#
# HOW A SCENE ENDS UP LIKE THAT, because nobody types it. Delete a texture that a
# TileSet is still painted with and Godot does not refuse and does not warn. It
# DEGRADES the reference: the healthy
#
#     [ext_resource type="Texture2D" path="res://art/tiles/c92.png" id="4_e1pj8"]
#
# is replaced on the next save by an embedded
#
#     [sub_resource type="CompressedTexture2D" id="..."]
#     load_path = "res://.godot/imported/c92.png-<hash>.ctex"
#
# which keeps drawing from the baked copy until that copy is cleaned, and then
# stops. That happened to elusion.tscn: c92.png was deleted as unused, 13 painted
# tiles in the main world scene lost their texture, and the only trace was a line
# 90 lines into an 85KB scene file.
#
# It is a text check because the failure is a text pattern, and because a runtime
# check would pass on the machine whose cache still holds the file - which is the
# one machine where the bug is invisible.
func _test_no_import_cache_references() -> void:
	section("IMPORT CACHE — no scene or resource points into .godot/")

	var offenders: Array[String] = []
	var scanned: Array[int] = [0]
	for folder in ["res://scene", "res://data", "res://art"]:
		_scan_import_cache_refs(folder, offenders, scanned)

	offenders.sort()
	check("the sweep found scenes and resources to check", scanned[0] > 0,
		"%d scanned" % scanned[0])
	check("nothing references the import cache", offenders.is_empty(),
		"\n         ".join(offenders))

	print("  %d scene/resource files scanned" % scanned[0])


func _scan_import_cache_refs(dir_path: String, offenders: Array[String], scanned: Array[int]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_import_cache_refs(full, offenders, scanned)
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			scanned[0] += 1
			var lines: PackedStringArray = FileAccess.get_file_as_string(full).split("\n")
			for i in range(lines.size()):
				if lines[i].contains("res://.godot/"):
					offenders.append("%s:%d  %s"
						% [full.trim_prefix("res://"), i + 1, lines[i].strip_edges().left(72)])
		entry = dir.get_next()
	dir.list_dir_end()


# =============================================================================
# EVERY FONT DRAWS WITHOUT THE OPERATING SYSTEM'S FONTS
# =============================================================================
# The town sign read "Goal: slay the Crowned" on Windows and a row of boxes with
# hex numbers in them in the browser - each box a missing letter's code, 47 6F
# 61 6C for "Goal". Its label pointed at a FontFile embedded in sign.tscn with
# no font data in it at all: the inspector's "New FontFile", never loaded. On a
# desktop Godot quietly borrows a system font for every glyph a font lacks, so
# the sign looked fine for months; a browser has no system fonts to borrow from.
#
# So: no FontFile anywhere may be empty unless it has fallbacks to draw with,
# and the sign's own text must be drawable by the font it actually resolves to.
# A SystemFont is fine - Godot documents that on platforms without system fonts
# it falls back to the default theme font, which is real.

func _test_every_font_draws_without_the_os() -> void:
	section("FONTS - every font has glyphs of its own (the browser has no system fonts)")

	var empty: Array[String] = []
	var fonts_seen: Array[int] = [0]
	var files: int = 0
	for folder in ["res://scene", "res://assets", "res://data", "res://src"]:
		for path in _all_files_under(folder, ".tscn") + _all_files_under(folder, ".tres"):
			files += 1
			_find_empty_fonts(path, empty, fonts_seen)
	empty.sort()
	check("the sweep read the scenes and resources", files > 50, "%d files" % files)
	print("  %d files read, %d embedded or standalone FontFiles among them" % [files, fonts_seen[0]])
	check("no FontFile is empty (no data and nothing to fall back on)", empty.is_empty(),
		"\n         ".join(empty))

	var packed: PackedScene = load("res://scene/interactables/sign.tscn")
	var sign_node: Node = packed.instantiate() if packed != null else null
	var label: Label = sign_node.get_node_or_null("signpanel/label") as Label if sign_node != null else null
	check("the town sign has its label", label != null)
	if label != null:
		var font: Font = label.label_settings.font if label.label_settings != null \
				and label.label_settings.font != null else label.get_theme_font("font")
		var missing: Array[String] = []
		for i in range(label.text.length()):
			var ch: String = label.text.substr(i, 1)
			if ch != " " and (font == null or not font.has_char(label.text.unicode_at(i))):
				missing.append(ch)
		check("every letter on the sign is in the font it draws with, no system font needed",
			font != null and missing.is_empty(), "missing: %s" % "".join(missing))
	if sign_node != null:
		sign_node.free()


# A SAVE FROM A PLAYER OUTSIDE THE SCENE TREE reads the cached bag. It used to
# ask player.get_tree() for the HUD, which is null off the tree, and the SCRIPT
# ERROR ended save_character_state() half-way. Five of them sat in a run that
# read green until the run learned to count them (_watch_script_errors()).
func _test_a_save_from_outside_the_tree() -> void:
	section("SAVING - a player outside the scene tree still has a bag to save")
	var shape := GDScript.new()
	shape.source_code = "extends Node\nvar inventory_data: Array = [{\"item_id\": \"zz_loose\", \"quantity\": 2.0}]\n"
	shape.reload()
	var loose := Node.new()
	loose.set_script(shape)
	var bag: Array = CharacterData._capture_inventory(loose)
	check("the cached bag comes back, the quantity a whole number again",
		bag.size() == 1 and typeof((bag[0] as Dictionary).get("quantity")) == TYPE_INT
		and int((bag[0] as Dictionary).get("quantity")) == 2, bag)
	loose.free()


# Reads the file's text rather than loading it, so an empty FontFile embedded in
# a scene is found without instancing the scene, and a standalone .tres FontFile
# is judged the same way.
func _find_empty_fonts(path: String, empty: Array[String], fonts_seen: Array[int]) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if not text.contains("FontFile"):
		return
	var blocks: PackedStringArray = text.split("\n[")
	for i in range(blocks.size()):
		var block: String = blocks[i] if i == 0 else "[" + blocks[i]
		var header: String = block.get_slice("\n", 0)
		var is_font: bool = header.begins_with("[sub_resource type=\"FontFile\"") \
				or (header.begins_with("[gd_resource type=\"FontFile\"") and i == 0)
		if not is_font:
			continue
		fonts_seen[0] += 1
		var body: String = block if not header.begins_with("[gd_resource") else text
		var has_glyphs: bool = body.contains("\ndata = ") or body.contains("\nfallbacks = ")
		if not has_glyphs:
			empty.append("%s  %s" % [path.trim_prefix("res://"), header.left(70)])


# =============================================================================
# UNUSED PARAMETERS, BECAUSE GODOT'S OWN WARNING DOES NOT REACH THIS SUITE
# =============================================================================
# GDScript warns on a parameter that is never read, and the fix it asks for is a
# leading underscore: `_source_slot` means "deliberately unused". That warning is
# printed by the EDITOR when it parses a script. It does NOT surface through
# ResourceLoader.load() in a headless run - proven by deliberately introducing an
# unused variable and unreachable code and watching this suite stay silent.
#
# So the one class of regression this suite is structurally blind to is exactly
# the class an editing pass produces: delete the last line that read a parameter
# and the parameter is now dead, with nothing in a headless run to say so.
#
# THAT IS NOT HYPOTHETICAL. Removing a write-only `_current_slot` tracker from
# itemtooltip.gd left `source_slot` with no reader. The suite was green; the
# warning only appeared when the project was next opened in the editor. It also
# left a docstring describing a guarantee the file no longer made.
#
# A text check closes the gap. It matches Godot's own rule rather than inventing
# one - a parameter that does not begin with `_` and never appears in its
# function body - so anything it flags is something the editor is already
# complaining about, and underscoring it satisfies both at once.
#
# KNOWN LIMIT: it reads single-line `func` declarations, so a signature wrapped
# across lines is skipped rather than guessed at. 1,627 functions parse this way
# and one violation existed when it was written, so the blind spot is small and
# a missed warning still shows up in the editor as it always did.
func _test_no_unused_parameters() -> void:
	section("UNUSED PARAMETERS — what the editor warns about, checked headless")

	var offenders: Array[String] = []
	var funcs: Array[int] = [0]
	_scan_unused_params("res://src", offenders, funcs)

	offenders.sort()
	check("the sweep found functions to check", funcs[0] > 0, "%d found" % funcs[0])
	check("every parameter is read, or underscored to say it is not",
		offenders.is_empty(), "\n         ".join(offenders))

	print("  %d function signatures scanned" % funcs[0])


func _scan_unused_params(dir_path: String, offenders: Array[String], funcs: Array[int]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_unused_params(full, offenders, funcs)
		elif entry.ends_with(".gd"):
			var lines: PackedStringArray = FileAccess.get_file_as_string(full).split("\n")
			for i in range(lines.size()):
				var line: String = lines[i]
				if not line.begins_with("func "):
					continue
				var open_paren: int = line.find("(")
				var close_paren: int = line.rfind(")")
				if open_paren < 0 or close_paren < open_paren:
					continue            # signature spans lines; see KNOWN LIMIT
				funcs[0] += 1
				var fname: String = line.substr(5, open_paren - 5)
				var arglist: String = line.substr(open_paren + 1, close_paren - open_paren - 1)
				if arglist.strip_edges() == "":
					continue

				# The body: every following line that is blank or indented.
				var body: String = ""
				for j in range(i + 1, lines.size()):
					var raw: String = lines[j]
					if raw.strip_edges() != "" and not raw.begins_with("\t"):
						break
					if not raw.strip_edges().begins_with("#"):
						body += raw + "\n"

				# SPLIT AT TOP-LEVEL COMMAS ONLY. A plain split(",") breaks on
				# any default value that contains one -
				# `colour: Color = Color(0.95, 0.45, 0.35)` became three
				# "parameters", the last of them named "0.35)", and this check
				# reported it as unused. A false alarm is how a check gets
				# switched off, which CLAUDE.md says in as many words.
				for piece in _split_params(arglist):
					var pname: String = piece.strip_edges().split(":")[0].split("=")[0].strip_edges()
					if pname == "" or pname.begins_with("_"):
						continue
					if not _mentions_word(body, pname):
						offenders.append("%s:%d  %s() — '%s' is never read; underscore it"
							% [full.trim_prefix("res://"), i + 1, fname, pname])
		entry = dir.get_next()
	dir.list_dir_end()


func _split_params(arglist: String) -> PackedStringArray:
	"""One entry per parameter, ignoring commas nested inside brackets.

	`a: int, colour: Color = Color(1, 0, 0), flags: Array = [1, 2]` is three
	parameters, not seven. Depth counting is enough here: GDScript signatures
	nest brackets but never contain an unbalanced one, and a comma inside a
	string default would need quotes, which are counted too so that a default of
	"a, b" stays one parameter.
	"""
	var out := PackedStringArray()
	var depth: int = 0
	var in_string: bool = false
	var quote: String = ""
	var current: String = ""
	for index in arglist.length():
		var ch: String = arglist[index]
		if in_string:
			current += ch
			if ch == quote:
				in_string = false
			continue
		if ch == "\"" or ch == "'":
			in_string = true
			quote = ch
			current += ch
			continue
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(current)
			current = ""
			continue
		current += ch
	if current.strip_edges() != "":
		out.append(current)
	return out


func _mentions_word(haystack: String, word: String) -> bool:
	# Whole-word only. Without this, a parameter named `slot` counts itself as
	# used because the body mentions `slot_index`, which is how a check like this
	# quietly stops checking anything.
	var from: int = 0
	while true:
		var at: int = haystack.find(word, from)
		if at < 0:
			return false
		var before_ok: bool = at == 0 or not _is_word_char(haystack[at - 1])
		var after: int = at + word.length()
		var after_ok: bool = after >= haystack.length() or not _is_word_char(haystack[after])
		if before_ok and after_ok:
			return true
		from = at + 1
	return false


func _is_word_char(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")


# =============================================================================
# A THIRD-PARTY LICENCE HAS TO SHIP WITH THE THING IT LICENCES
# =============================================================================
# Some licences are not just permission, they are an OBLIGATION to carry the
# text. The SIL Open Font License is one: you may use the font in anything,
# commercially included, provided the notice and the licence travel with it.
#
# assets/fonts/NotoColorEmoji.ttf is Google's, under OFL 1.1 - read out of the
# font's own name table, not assumed:
#
#     Copyright 2022 Google Inc.
#     SIL Open Font License, Version 1.1
#     http://scripts.sil.org/OFL
#
# It shipped here with no licence file beside it, inside a folder assetlicense.md
# claimed for Elusion Studios. That is the same mistake as the item tiles and the
# behemoth crown, in a folder nobody had thought to look at, and it is the reason
# this check exists rather than a note somewhere.
#
# THE FILE IS NOT WRITTEN FROM MEMORY. A licence transcribed approximately is
# worse than one that is absent, because it looks discharged. OFL.txt ships in
# the noto-emoji release the font came from; copy that one in.
#
# Keyed on the LICENSED file, not the folder: a font added later without its
# licence is the failure to catch, and a folder-level rule would pass the moment
# any one licence file existed.
#
# SEVERAL ACCEPTABLE NAMES, because the upstream project does not agree with
# itself. googlefonts/noto-emoji's README links fonts/LICENSE and that link 404s;
# a Google Fonts family download ships OFL.txt. Both are the same text. Insisting
# on one spelling would mean fighting the check over a filename instead of
# satisfying the licence, which is how a check gets switched off.
const THIRD_PARTY_LICENCES := {
	"res://assets/fonts/NotoColorEmoji.ttf": "res://assets/fonts",
}

const LICENCE_FILENAMES := ["OFL.txt", "OFL", "LICENSE", "LICENSE.txt", "LICENCE", "LICENCE.txt"]


func _test_third_party_licences() -> void:
	section("THIRD-PARTY LICENCES — the text ships with the thing it licences")

	for asset in THIRD_PARTY_LICENCES:
		var folder: String = THIRD_PARTY_LICENCES[asset]
		if not FileAccess.file_exists(asset):
			# The asset is gone, so the obligation is too. Say so rather than
			# failing, and rather than silently passing.
			print("  note  %s is not present; its licence is not required"
				% asset.get_file())
			continue

		var found: String = ""
		for filename in LICENCE_FILENAMES:
			if FileAccess.file_exists(folder.path_join(filename)):
				found = filename
				break

		check("%s ships with its licence text" % asset.get_file(), found != "",
			"none of %s found in %s. Copy it from the release the asset came from - a licence written out by hand is worse than an absent one, because it looks discharged."
				% [", ".join(LICENCE_FILENAMES), folder])
		if found != "":
			print("         found %s" % folder.path_join(found))

	print("  %d licensed third-party asset(s) checked" % THIRD_PARTY_LICENCES.size())


# =============================================================================
# AUDIO — A FILLED SLOT MUST POINT AT A FILE THAT EXISTS
# =============================================================================
# audio.gd's SOUNDS table is 31 named slots, each starting as "". Empty means
# "not recorded yet", and audio.gd is explicit that this is silence on purpose
# rather than an error - which is right, and is why the slots can be filled one
# at a time as the sounds get made.
#
# A FILLED SLOT IS A DIFFERENT THING. audio.gd already guards it: a path that
# does not resolve gets one push_warning and returns null. The gap is WHEN. That
# warning fires the first time the sound is actually triggered, so a typo in
# "music_crypt" stays invisible until somebody walks into the crypt, and a typo
# in "player_death" until somebody dies. It is correct behaviour reported at the
# wrong moment - the whole project's recurring failure shape.
#
# This asserts the same thing at commit time, before anyone plays.
#
# THE BUSES TOO, because they fail even more quietly. Every pooled player is
# assigned to "SFX" and the music player to "Music". Rename a bus in
# default_bus_layout.tres and Godot does not error - it silently routes those
# players to Master, so the sound still plays and the volume sliders stop
# working, which is a thing you would chase in the options screen for an hour.
const AUDIO_BUSES := ["Master", "Music", "SFX"]


func _test_audio_paths() -> void:
	section("AUDIO — filled slots resolve, and the buses they play on exist")

	var audio_script := require_script("res://src/systems/audio.gd", "audio.gd")
	if audio_script == null:
		return
	var sounds: Dictionary = audio_script.get_script_constant_map().get("SOUNDS", {})

	check("the SOUNDS table is readable", not sounds.is_empty(), "%d slots" % sounds.size())

	var missing: Array[String] = []
	var empty: Array[String] = []
	var filled: int = 0
	for id in sounds:
		var path: String = String(sounds[id])
		if path == "":
			empty.append(String(id))
			continue          # not recorded yet - silent on purpose
		filled += 1
		if not ResourceLoader.exists(path):
			missing.append("%s -> %s" % [id, path])
	missing.sort()
	empty.sort()
	check("every filled sound slot points at a file that exists",
		missing.is_empty(), "\n         ".join(missing))

	# A ONE-SHOT THAT LOOPS NEVER STOPS. Godot's import dock has a Loop box,
	# and play() hands the stream to a pool player that is never told to stop,
	# so a sound effect imported looping plays until twelve more sounds push
	# it out of the pool. Music is exempt: play_music() sets the loop itself.
	var looping: Array[String] = []
	for id in sounds:
		var sfx_path: String = String(sounds[id])
		if sfx_path == "" or String(id).begins_with("music_") or not ResourceLoader.exists(sfx_path):
			continue
		var stream: AudioStream = load(sfx_path)
		if (stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop) \
				or (stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED) \
				or (stream is AudioStreamMP3 and (stream as AudioStreamMP3).loop):
			looping.append("%s -> %s" % [id, sfx_path])
	looping.sort()
	check("no sound effect is imported looping", looping.is_empty(),
		"untick Loop in the Import dock: " + ", ".join(looping))

	for bus_name in AUDIO_BUSES:
		check("the '%s' audio bus exists" % bus_name,
			AudioServer.get_bus_index(bus_name) >= 0,
			"players assigned to a missing bus fall back to Master, silently")

	# =========================================================================
	# EVERY ID ANYTHING PLAYS IS REGISTERED
	# =========================================================================
	# THIS ONE HAS ALREADY HAPPENED. "cook" was played by cookingscreen.gd
	# before it was registered, so every fish finishing on the fire produced a
	# push_warning instead of a sound - and a push_warning in a running game is
	# a line nobody sees. An unassigned id is a deliberate no-op; an id that is
	# not in the table at all is a typo, and only the table can tell them apart.
	#
	# READ OUT OF THE CALL EXPRESSION, NOT OFF THE LINE, because of that very
	# call site:
	#
	#     Audio.play("refused" if burnt else "cook")
	#
	# A check matching Audio.play("<id>") sees "refused" and never learns that
	# "cook" is played at all - so the check would have missed the one bug it
	# is named after. Every string literal between the parentheses is taken.
	#
	# WHAT IT CANNOT SEE, said plainly rather than implied: an id held in a
	# variable. There is no such call today and this would not notice one.
	var played: Dictionary = {}
	var unregistered: Array[String] = []
	for script_path in _scripts_under("res://src"):
		# THE SCANNER DOES NOT SCAN ITSELF. This file contains the string
		# "Audio.play" in the code above - inside find() - so including it made
		# the check read its own source and report the literal as an id. A
		# scanner that is part of what it scans is measuring itself.
		if script_path == "res://src/tools/testrunner.gd":
			continue
		var body: String = _code_only(FileAccess.get_file_as_string(script_path))
		var at: int = body.find("Audio.play")
		while at != -1:
			var open_at: int = body.find("(", at)
			var close_at: int = body.find(")", open_at)
			if open_at == -1 or close_at == -1:
				break
			var args: String = body.substr(open_at, close_at - open_at)
			var quote: int = args.find("\"")
			while quote != -1:
				var end_quote: int = args.find("\"", quote + 1)
				if end_quote == -1:
					break
				var id: String = args.substr(quote + 1, end_quote - quote - 1)
				if id != "" and not sounds.has(id):
					var note: String = "%s (%s)" % [id, script_path.get_file()]
					if not unregistered.has(note):
						unregistered.append(note)
				if id != "":
					played[id] = true
				quote = args.find("\"", end_quote + 1)
			at = body.find("Audio.play", close_at)

	check("something in the game asks for a sound at all", played.size() > 0,
		played.size())
	check("and every id it asks for is registered", unregistered.is_empty(),
		unregistered)

	# =========================================================================
	# ASSIGNED, OR STILL ARRIVING - AND THE REST NAMED EVERY RUN
	# =========================================================================
	# Nobody ships a game and fails to notice it makes no noise at all. What
	# ships unnoticed is twenty-six sounds assigned and five forgotten, because
	# the boot line still prints a number and nothing reads it.
	#
	# This used to FAIL the middle. Then the first sound arrived (teleport, day
	# 2), recorded by the owner on his own Stylophone, and the middle turned out
	# to be where the game will sit for weeks while the rest are recorded one
	# at a time. A suite that is red for weeks is a suite nobody reads, which is
	# the failure this check exists to prevent. So anything short of all is a
	# SKIP that counts what is filled and prints every empty id; all is a PASS.
	# docs/audio.md is the list to work from.
	if not empty.is_empty():
		skipped += 1
		var state: String = ("the game is deliberately silent" if filled == 0
			else "%d still to record, listed above" % empty.size())
		if filled > 0:
			print("  still empty: %s" % ", ".join(empty))
		skips.append("the sound registry is filled in   (%d of %d assigned; %s - see docs/audio.md)"
			% [filled, sounds.size(), state])
		_say("  skip  the sound registry is filled in   (%d of %d assigned, %s)"
			% [filled, sounds.size(), state])
	else:
		check("the sound registry is filled in", empty.is_empty(),
			"%d of %d assigned, still empty: %s"
				% [filled, sounds.size(), ", ".join(empty)])

	# REGISTERED AND NEVER ASKED FOR: printed, not checked. These are hooks not
	# yet written rather than mistakes, and a check that went red on day one
	# for six of them would be switched off within a week. The list belongs in
	# front of whoever fills the table, not discovered by wondering why a sound
	# never plays.
	var unplayed: Array[String] = []
	for id in sounds:
		if not played.has(String(id)):
			unplayed.append(String(id))
	unplayed.sort()
	if not unplayed.is_empty():
		print("  %d registered that nothing plays yet: %s"
			% [unplayed.size(), ", ".join(unplayed)])

	print("  %d of %d slots filled; %d ids played; %d bus(es) checked"
		% [filled, sounds.size(), played.size(), AUDIO_BUSES.size()])


# =============================================================================
# EVERY PORTAL MAKES A SOUND
# =============================================================================
# Day 2: the teleport sound went in and played at two portals out of four. The
# town's way out to the field and the field's arrival portal were silent,
# because each door asks for its own sound and nothing noticed one that did
# not. The owner found both by walking through them.
#
# Two halves. Every function under src/world that changes the area must ask
# Audio for a sound before it does: a text check, because a real
# SceneTransition in the middle of the suite would end the suite. And the
# field's arrival portal is driven for real through leavetown.gd, counting
# pool players: quiet when you land in it, the teleport sound when it closes
# behind you.
func _test_every_portal_makes_a_sound() -> void:
	section("PORTALS — every way between areas makes a sound")

	var silent: Array[String] = []
	var doors: int = 0
	for script_path in _scripts_under("res://src/world"):
		var code: String = _code_only(FileAccess.get_file_as_string(script_path))
		var at: int = code.find("SceneTransition.change_scene(")
		while at != -1:
			doors += 1
			var func_at: int = maxi(code.rfind("\nfunc ", at), 0)
			var sound_at: int = code.find("Audio.play", func_at)
			if sound_at == -1 or sound_at > at:
				silent.append("%s:%d" % [script_path.get_file(), code.substr(0, at).count("\n") + 1])
			at = code.find("SceneTransition.change_scene(", at + 1)
	check("the scan finds the doors between areas", doors >= 3, doors)
	check("every one plays a sound before the area changes", silent.is_empty(),
		", ".join(silent))

	# The town's way out: after the arrival-only return, before the change.
	var exit_src: String = FileAccess.get_file_as_string("res://src/world/leavetown.gd")
	var entered: int = _first_code_index(exit_src, "func _on_body_entered", 0)
	var entered_end: int = _first_code_index(exit_src, "\nfunc ", entered + 1)
	var bail: int = _within(_first_code_index(exit_src, "return", entered), entered_end)
	var exit_sound: int = _within(_first_code_index(exit_src, "Audio.play(\"teleport\")", entered), entered_end)
	var change: int = _within(_first_code_index(exit_src, "SceneTransition.change_scene(", entered), entered_end)
	check("the town's way out plays the teleport sound as you go through",
		exit_sound != -1 and change != -1 and exit_sound < change)
	check("  and not before the arrival-only return, so landing is quiet",
		bail != -1 and exit_sound > bail)

	# The field's arrival portal, for real.
	var tele_stream: AudioStream = Audio._stream_for("teleport")
	if tele_stream == null:
		check("the teleport sound loads", false, "Audio._stream_for(\"teleport\") is null")
		return
	var playing_teleport := func() -> int:
		var n: int = 0
		for p in Audio._sfx_pool:
			if p.playing and p.stream == tele_stream:
				n += 1
		return n
	for p in Audio._sfx_pool:
		if p.stream == tele_stream:
			p.stop()

	# Untyped: arrival_only and the rest are leavetown.gd's, not Area2D's.
	var portal = (load("res://src/world/leavetown.gd") as GDScript).new()
	portal.arrival_only = true
	portal.vanish_after_first_use = true
	add_child(portal)
	# Not added to the tree: a second "Player" under this node would be
	# renamed, and the portal knows the player by that name.
	var lander := Node2D.new()
	lander.name = "Player"

	portal._on_body_entered(lander)
	check("landing in the field's arrival portal makes no sound",
		playing_teleport.call() == 0, playing_teleport.call())
	portal._on_body_exited(lander)
	check("walking off it closes it with the teleport sound",
		playing_teleport.call() == 1, playing_teleport.call())
	portal._on_body_entered(lander)
	portal._on_body_exited(lander)
	check("  once: it closes one time", playing_teleport.call() == 1,
		playing_teleport.call())

	for p in Audio._sfx_pool:
		if p.stream == tele_stream:
			p.stop()
	portal.queue_free()
	lander.free()
	print("  %d doors between areas, %d silent; the arrival portal driven both ways"
		% [doors, silent.size()])


# =============================================================================
# THE CHAT PICTURE CACHE IS BOUNDED BY THE LOG, NOT BY THE SESSION
# =============================================================================
# chatpanel.gd caps each channel at LINES_KEPT and its own comment says why: an
# uncapped log is "a slowly growing pile of nodes nobody can scroll back to".
# That cap reached the LINES and not the pictures. _pictures held the decoded
# frames of every image anybody had posted, keyed by id, for the whole session -
# the line was long gone and the megabytes were not. At UPLOAD_MAX_SIDE 1024 that
# is a few MB per picture, and an animated one holds a texture per frame.
#
# _sweep_pictures() drops any id no kept line can reach, called at the moment a
# line is trimmed. No cache size to tune: the log's window is already the right
# answer, because an image nothing can scroll to is an image nobody can open.
#
# A TEXT CHECK, and openly a regression guard rather than a behavioural test.
# Asserting the real thing would mean driving a live panel through 100+ lines
# with pictures attached, and the failure has no symptom short of watching memory
# climb over an hour of busy chat - which is exactly how it went unnoticed.
func _test_chat_picture_sweep() -> void:
	section("CHAT PICTURES — the cache is swept, not kept for the session")

	var src: String = FileAccess.get_file_as_string("res://src/ui/chat/chatpanel.gd")
	check("chatpanel.gd is readable", src.length() > 0)
	check("_pictures is erased somewhere", src.contains("_pictures.erase("),
		"without this every image posted stays decoded in memory for the session")
	check("and the sweep is wired to the line trim",
		src.contains("_sweep_pictures()") and src.contains("if trimmed:"),
		"the sweep exists but nothing calls it when a line scrolls off")
	check("the open viewer is spared", src.contains("live[_viewing]"),
		"closing and reopening a picture would refetch it from the server")

	print("  the log window bounds the cache; no separate size to tune")


# =============================================================================
# A DELETED LINE HAS TO LEAVE THE SCREENS THAT ALREADY HAVE IT
# =============================================================================
# The chat feed was APPEND-ONLY, and that made it unmoderatable. _poll() asks
# for messages past its cursor and calls _add_line(); the only way a line ever
# left was pop_front() at LINES_KEPT. So a mod deleting a message stopped it
# reaching anybody who had not read it yet and did nothing about the people who
# had - it stayed on their screen until a hundred more lines pushed it off, or
# until they closed the game. That is exactly the set of players the deletion
# was for.
#
# Worse for pictures. /api/chat/delete now drops the image row too, so the bytes
# 404 - but a client that already decoded it holds the texture in _pictures, and
# again that is the people who saw it.
#
# THIS ONE IS NOT A TEXT CHECK. _remove_lines() is pure logic over _feeds, so the
# script can be instantiated bare, handed real feed contents and asked. _ready()
# is never called - it needs nodes - so the test fills _feeds itself, which is
# the only thing the function reads.
func _test_chat_deletions_reach_the_client() -> void:
	section("CHAT DELETIONS — a line the server removed leaves the feed")

	var script: Script = load("res://src/ui/chat/chatpanel.gd") as Script
	check("chatpanel.gd compiles and can be instantiated", script != null and script.can_instantiate())
	if script == null or not script.can_instantiate():
		return

	var panel: Object = script.new()
	check("a bare panel exists", panel != null)
	if panel == null:
		return

	# _ready() is what normally builds these, and it wants nodes. The function
	# under test reads nothing else.
	var feeds: Dictionary = {}
	for channel in ["world", "friends", "private", "guild"]:
		feeds[channel] = {"cursor": 0, "lines": [], "unread": false}
	feeds["world"]["lines"] = [
		{"kind": "chat", "id": 10, "by": "a", "body": "fine"},
		{"kind": "chat", "id": 11, "by": "b", "body": "offensive"},
		{"kind": "image", "id": 12, "by": "b", "body": "", "image": "deadbeef"},
		{"kind": "system", "body": "a notice with no id"},
	]
	panel.set("_feeds", feeds)
	panel.set("_pictures", {"deadbeef": {"frames": []}})
	panel.set("_viewing", "")

	var went: int = panel.call("_remove_lines", "world", [11])
	var left: Array = panel.get("_feeds")["world"]["lines"]
	check("the named line goes", went == 1 and left.size() == 3, [went, left.size()])
	check("and it is the right one",
		not _feed_holds_id(left, 11) and _feed_holds_id(left, 10) and _feed_holds_id(left, 12),
		left)

	# A SYSTEM NOTICE HAS NO SERVER ID, which in this project means id 0. A
	# removal list must not be able to sweep those away, and "id" defaulting to 0
	# is exactly the shape that would.
	went = panel.call("_remove_lines", "world", [0])
	check("an id of 0 removes nothing", went == 0 and panel.get("_feeds")["world"]["lines"].size() == 3,
		"a system notice carries no id; 0 must not match it")

	# THE PICTURE GOES WITH THE LAST LINE THAT SHOWED IT, via the existing sweep.
	went = panel.call("_remove_lines", "world", [12])
	check("removing the last line showing a picture drops the picture",
		went == 1 and not panel.get("_pictures").has("deadbeef"),
		panel.get("_pictures").keys())

	# AND THE OPEN VIEWER IS CLOSED, which is the case worth building this for.
	# _sweep_pictures() deliberately SPARES _viewing, so a sweep alone would keep
	# the picture alive and leave the overlay up in front of the one player most
	# needing it gone.
	var again: Dictionary = {}
	for channel in ["world", "friends", "private", "guild"]:
		again[channel] = {"cursor": 0, "lines": [], "unread": false}
	again["world"]["lines"] = [{"kind": "image", "id": 20, "by": "b", "image": "cafe"}]
	panel.set("_feeds", again)
	panel.set("_pictures", {"cafe": {"frames": []}})
	panel.set("_viewing", "cafe")

	panel.call("_remove_lines", "world", [20])
	check("the open viewer closes when its picture is deleted",
		str(panel.get("_viewing")) == "",
		"the player staring at it full-screen is who the deletion is for")
	check("...and only then is the picture dropped",
		not panel.get("_pictures").has("cafe"),
		"close_viewer() has to run BEFORE the sweep, or _viewing spares it")

	# REPEATS ARE FREE. The server announces a deletion for the whole window, so
	# the same id arrives on around forty consecutive polls by design.
	var repeat: int = panel.call("_remove_lines", "world", [20, 20, 20])
	check("an id already gone costs nothing the second time", repeat == 0, repeat)

	var other: int = panel.call("_remove_lines", "private", [20])
	check("and a channel that never held it is untouched", other == 0, other)

	panel.free()

	# The wiring, which no bare instance can prove.
	var src: String = FileAccess.get_file_as_string("res://src/ui/chat/chatpanel.gd")
	check("the poll reads the server's removed list", src.contains("data.get(\"removed\", [])"),
		"the function works and nothing calls it")
	check("and it runs AFTER the additions",
		src.find("_add_line(asked, _line_from_server(") < src.find("var removed = data.get(\"removed\""),
		"a line posted and deleted inside one poll would survive")

	print("  a feed that can only grow cannot be moderated")


# =============================================================================
# THE SECURITY POLICY SAYS WHAT IS TRUE OF THIS CLIENT
# =============================================================================
# SECURITY.md is what GitHub shows under this repository's Security tab, and it
# is read by people who cannot check it themselves. Everything it claims about
# the client has to still be true of the client.
#
# Four sentences on that page are load-bearing, and each names something in the
# code that could be changed without anyone rereading the page. So the page does
# not get to assert them - the code is asked.
func _test_security_policy() -> void:
	section("SECURITY.md — what it says about the client is still true")

	var raw: String = FileAccess.get_file_as_string("res://SECURITY.md")

	# WRAPPED PROSE IS STILL ONE SENTENCE, and this is the third time today that
	# a text check has been fooled by a newline landing mid-phrase. Markdown wraps
	# wherever the column ran out, so "the backpack\nledger is still..." does not
	# contain "backpack ledger" at all. Collapse the whitespace before looking, or
	# the check fails on a page that says exactly the right thing.
	var doc: String = " ".join(raw.split("\n", false))
	while doc.contains("  "):
		doc = doc.replace("  ", " ")

	check("SECURITY.md exists", raw.length() > 0,
		"the Security tab has a report button and would have no policy behind it")
	if raw.length() == 0:
		return

	check("it points at the server's model rather than restating one",
		doc.contains("elusion-api") and doc.contains("SECURITY.md"),
		"two security pages that can disagree is worse than one")

	# "Api.role decides which buttons are drawn and refuses nothing."
	var api_src: String = FileAccess.get_file_as_string("res://src/systems/api.gd")
	check("role is still held in memory and never written to session.cfg",
		api_src.contains("Held only in memory and never written to session.cfg"),
		"a permission that lives in a file is a permission that can be edited")

	# "gated on OS.is_debug_build() AND a rank of mod or above"
	var player_src: String = FileAccess.get_file_as_string("res://src/characters/player.gd")
	check("the debug keys are still gated on a debug build AND a rank",
		player_src.contains("OS.is_debug_build() and Api.role_at_least("),
		"SECURITY.md describes this gate; if it changes, the page is lying")
	check("and the page says plainly that it is a rule, not a defence",
		doc.contains("rule, not a defence"),
		"claiming it stops a modified client would be the comforting lie")

	# "The session token lives in user://session.cfg and is a bearer credential."
	check("the token still lives where the page says it does",
		api_src.contains("user://session.cfg"), api_src.contains("session.cfg"))

	# The honest limit this page used to inherit from the server's list - "the
	# backpack ledger is still client-declared" - closed when the bag became the
	# server's. The page has to say so in its place, and say it truly: the bag
	# routes exist and a save no longer carries the bag.
	check("the page no longer calls the backpack client-declared, and says whose it is",
		not doc.contains("backpack ledger is still client-declared")
		and doc.contains("the backpack and the bank are the server's"),
		"a closed gap left on the page reads as still open; one dropped silently reads as forgotten")
	check("  which the code bears out: the bin is a request, and a save carries no bag",
		_code_src("res://src/ui/inventory/inventorycontainer.gd").contains("CARRY_DISCARD_PATH")
		and not _code_src("res://src/systems/serverstorage.gd").contains("\"/api/character/inventory\""))

	check("and it tells people where to report without publishing an inbox",
		doc.contains("Report a vulnerability") and not doc.contains("@gmail"),
		"a documented security address is a documented spam target")

	# "With Remember me off the token lives in memory and is not stored."
	check("Remember me off still keeps the token out of storage",
		doc.contains("Remember me\" off the token lives in memory")
		and api_src.contains("Off, the token lives in memory only and session.cfg is removed"),
		"the browser paragraph promises this; the code has to still do it")

	# "--server=, ELUSION_SERVER and user://server.cfg all override the address,
	# and plain http:// is accepted." Both halves are a warning to the reader,
	# so both are asked of the code: an override removed, or http refused, makes
	# the page wrong in the reassuring direction.
	var resolve: String = _func_body(api_src, "static func _resolve_base_url(")
	check("the three overrides the page names are the three the game reads",
		doc.contains("--server=") and doc.contains("ELUSION_SERVER") and doc.contains("user://server.cfg")
		and resolve.contains("\"--server=\"") and resolve.contains("\"ELUSION_SERVER\"")
		and api_src.contains("SERVER_OVERRIDE_FILE := \"user://server.cfg\""))
	check("  and plain http:// is still accepted, as the page warns",
		_func_body(api_src, "static func _clean_base_url(").contains("url.begins_with(\"http://\")"),
		"if http is refused now, say so on the page")

	# "The pack ... holds the scripts compiled but not encrypted."
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var encrypted: Array = []
	for sec in presets.get_sections():
		if not sec.ends_with(".options") and presets.get_value(sec, "encrypt_pck", false) != false:
			encrypted.append(presets.get_value(sec, "name", sec))
	check("no export encrypts its pack, as the page says", doc.contains("encrypt_pck=false")
		and encrypted.is_empty(), encrypted)

	print("  the page is checked against the client, not trusted")


# =============================================================================
# THE CLIENT DOES NOT PUSH SKILLS
# =============================================================================
# The last piece of E-2. All six skills are server-granted, and
# PUT /api/character/skills drops every skill name it accepts - so the client's
# push could not write anything.
#
# It was not free, though, which is why this is a check and not a tidy-up.
# _put_if_changed() only sends when the body changes, and the body is the six
# skill levels, which the SERVER moves on almost every kill. The fingerprint
# changed constantly, so nearly every save bought a round trip whose whole effect
# was to be validated and thrown away.
#
# Text checks, because proving it needs a live server, a character and a kill.
func _test_skills_are_not_pushed() -> void:
	section("SKILLS — the client stopped pushing what it cannot write")

	var src: String = FileAccess.get_file_as_string("res://src/systems/serverstorage.gd")
	check("serverstorage.gd is readable", src.length() > 0)

	check("nothing pushes /api/character/skills any more",
		not src.contains("\"/api/character/skills\""),
		"the route drops every skill it accepts; the request buys nothing")
	check("and the body builder went with it",
		not src.contains("func _skills_body("),
		"an uncalled builder is the thing that gets wired back up by accident")

	# THE OTHER SECTIONS MUST STILL GO. Removing one line from a list of
	# awaits is a very easy way to remove two. (The bag went on purpose: it is
	# the server's now, and _test_the_bag_is_the_servers() holds that.)
	for path in ["/api/save", "/api/player/status"]:
		check("%s is still pushed" % path, src.contains("\"%s\"" % path),
			"this is a skills change, not a save change")

	# THE SEED HAS TO MATCH THE PUSH. _last_pushed is seeded on load so the first
	# save of a session does not push everything; a seed for a section nobody
	# pushes is harmless, but a seed MISSING for one that is pushed makes that
	# section push once per session forever.
	for key in ["save:%d", "status:%d"]:
		check("the seed still covers %s" % key.replace("%d", "N"),
			src.contains("_last_pushed[\"%s\"" % key),
			"a section pushed but not seeded sends once every session for nothing")
	check("and no longer seeds skills",
		not src.contains("_last_pushed[\"skills:%d\"] = JSON"),
		"seeding a section nobody pushes is a fingerprint nobody compares")

	# THE READ SIDE HAS TO SURVIVE THE PUSH BEING REMOVED. The server still SENDS
	# all six on every character load; if unpacking them goes too, a character
	# comes back with no skills and nothing errors.
	#
	# THESE TWO CHECKS USED TO NAME SKILL_IDS, AND BOTH PASSED A SABOTAGE THAT
	# RENAMED IT. `src.contains("const SKILL_IDS")` matches inside
	# "const SKILL_IDS_UNUSED" - the same whole-word trap
	# _test_no_unused_parameters() documents, where a parameter called `slot`
	# counts itself as used because the body says `slot_index`.
	#
	# Tightening the match would have been the wrong fix. A consistent RENAME
	# breaks nothing, so a check that fails on one is noise; what must not happen
	# is the unpacking DISAPPEARING. So these ask about the behaviour instead of
	# the name, which is both correct and rename-proof.
	check("the read side still takes skills off the server response",
		src.contains("data.get(\"skills\", {})"),
		"the server sends all six on every load; nothing would read them")
	check("and still writes both halves onto the slot",
		src.contains("_xp\"] = _int(entry.get(\"xp\"") or src.contains("+ \"_xp\"] = _int("),
		"a level with no xp beside it is a character that forgets its progress")

	print("  server grants them, the client reads them, nobody pushes them")


# =============================================================================
# GOD MODE EARNS NOTHING
# =============================================================================
# The owner can turn damage off to test without dying a hundred times. The whole
# risk in that feature is one ordering decision.
#
# take_damage() ends by calling gain_defense_xp(), which reports the RAW amount
# to /api/skill/train - and the server GRANTS AND STORES that XP. So the obvious
# implementation, "let the hit land and then heal back to full", would train
# defense continuously at no risk, and E-2's rate cap would not catch it: that
# cap bounds XP per second, and an invincible character parked in a pile of
# enemies sits at the honest ceiling all day.
#
# So the guard must come BEFORE the hp change and before the XP. This checks
# that ordering by position, which is the one thing that actually matters.
func _test_god_mode_earns_nothing() -> void:
	section("GOD MODE — the hit never happened, so nothing is earned")

	var src: String = FileAccess.get_file_as_string("res://src/characters/player.gd")
	check("player.gd is readable", src.length() > 0)

	var guard: int = src.find("if GameState.god_mode and Api.role_at_least(")
	check("take_damage() has a god-mode guard", guard != -1,
		"without it the feature does not exist")

	var body: int = src.find("func take_damage(")
	var xp_call: int = _first_code_index(src, "gain_defense_xp(", body)
	var hp_write: int = _first_code_index(src, "hp = clamp(hp - reduced_amount", body)
	check("the guard is inside take_damage()", guard > body and body != -1, [body, guard])
	check("THE GUARD COMES BEFORE THE HP CHANGE", guard < hp_write and hp_write != -1,
		"a guard after the write is a heal, not immunity")
	check("AND BEFORE THE DEFENSE XP", guard < xp_call and xp_call != -1,
		"this is the one that matters: past it, god mode mints server-granted XP")

	# ONE STATEMENT OF THE POLICY. Api.GOD_MODE_MIN_ROLE holds the rank, the same
	# way DEBUG_KEYS_MIN_ROLE does for the keys beside it - so this suite asserts
	# the rule itself rather than a second copy of it, and a literal rank string
	# at any of these sites is the drift this is here to catch.
	var api_src: String = FileAccess.get_file_as_string("res://src/systems/api.gd")
	check("the rank lives in api.gd as a constant",
		api_src.contains("const GOD_MODE_MIN_ROLE :="),
		"a threshold written at each call site is a threshold that drifts")
	check("and it is at least dev - not the mod the debug keys take",
		api_src.contains("const GOD_MODE_MIN_ROLE := \"dev\"")
			or api_src.contains("const GOD_MODE_MIN_ROLE := \"owner\""),
		"the keys beside it hand out items; this decides whether the game can be lost")

	# THE KEY WORKS IN A RELEASE BUILD, and that is deliberate. Everything past
	# _staff_debug_allowed() also needs OS.is_debug_build(), because those keys
	# hand out gear and currency. God mode hands out nothing and is for testing
	# the REAL build against the REAL server, so requiring a debug export would
	# leave a dev with no way in on the thing they were asked to check.
	var gate: int = _first_code_index(src, "if not _staff_debug_allowed():", 0)
	var key: int = _first_code_index(src, "event.keycode == KEY_G", 0)
	check("Ctrl+G is handled before the debug-build gate",
		key != -1 and gate != -1 and key < gate,
		"inside it, a dev testing a release build has no way to turn it on")
	check("and it ignores a keypress while somebody is typing",
		src.contains("not _typing_in_ui()"),
		"this runs in release builds now, where chat is open")

	var toggle: int = src.find("func _toggle_god_mode(")
	check("there is a toggle", toggle != -1)
	var refusal: int = src.find("if not Api.role_at_least(Api.GOD_MODE_MIN_ROLE):", toggle)
	check("the toggle refuses below the threshold",
		refusal != -1 and refusal < src.find("GameState.god_mode = not", toggle),
		"the refusal has to come before the flip, not after it")
	check("and neither site hardcodes a rank",
		not src.contains("Api.role_at_least(\"dev\")")
			and not src.contains("GameState.god_mode and Api.is_owner"),
		"a rank typed at the call site is the second copy of the rule")

	# THE PANEL IS THE SECOND WAY IN, and a disabled button is a UI state rather
	# than an authorisation - so it checks the rank itself.
	var panel: String = FileAccess.get_file_as_string("res://src/ui/owner/ownerpanel.gd")
	check("the panel has a god-mode switch", panel.contains("%godmodebutton"),
		"the scene node and the script have to agree on the unique name")
	check("and it checks the rank rather than trusting the button",
		panel.contains("if not Api.role_at_least(Api.GOD_MODE_MIN_ROLE):"),
		"disabled is a look, not a permission")
	check("the switch mirrors the flag without re-emitting",
		panel.contains("set_pressed_no_signal(GameState.god_mode)"),
		"writing button_pressed fires toggled, which would flip what it mirrors")
	check("and it re-reads on open, because Ctrl+G moves the same flag",
		panel.contains("_sync_god_mode_button()"),
		"a switch that remembers its own state disagrees with the keyboard")

	var scene: String = FileAccess.get_file_as_string("res://scene/ui/owner/ownerpanel.tscn")
	check("the scene actually carries the switch",
		scene.contains("name=\"godmodebutton\"") and scene.contains("CheckButton"),
		"a unique name the scene does not have is a null the panel silently skips")

	# The flag lives where a scene change cannot clear it and a restart must.
	var gs: String = FileAccess.get_file_as_string("res://src/systems/gamestate.gd")
	check("the flag is transient state on GameState", gs.contains("var god_mode: bool = false"),
		"on the player it would switch itself off at every town gate")
	check("and GameState is still the never-saved file it says it is",
		gs.contains("must NOT survive a restart"),
		"god mode persisted across sessions is god mode somebody forgot about")

	# The player has to be TOLD what it costs, because a flat defense bar an
	# hour later is a worse way to find out.
	check("the notice names the defence XP cost (the game's spelling, as on the stats screen)",
		src.contains("no damage taken, and no defence XP"),
		"the surprising half is not that you stopped dying")

	print("  no damage, no death, no floating number, and no XP")


# =============================================================================
# TELEPORT IS JOINED UP, AND NOBODY LANDS IN A WALL
# =============================================================================
# POST /api/staff/teleport has existed for a while and characterhud.gd has always
# known how to RECEIVE one. Nothing had ever ISSUED one - the feature was built
# from both ends and never joined in the middle.
#
# TWO SEPARATE RULES, and the second is the one with teeth:
#
#   NOBODY STACKS. The server already handles this: teleport_offset() packs a
#   group into hexagonal rings at TELEPORT_SPACING and hands each client its own
#   final coordinates. But slot 0 is (0,0) - dead on the destination - and the
#   destination is wherever the person who pressed the button is standing. So
#   the panel asks for a spot BESIDE itself, never its own.
#
#   NOBODY LANDS IN THE SCENERY. That one the server cannot do, because it has
#   no idea where the walls are. Fifty people in the town square puts the outer
#   ring 192px out. The client holds the collision shapes, so the nudge lives
#   there - in the RECEIVE path, which every teleported player goes through, not
#   only the one issued from this panel.
func _test_teleport_is_wired() -> void:
	section("TELEPORT — issued, and landed somewhere a character fits")

	var panel: String = FileAccess.get_file_as_string("res://src/ui/owner/ownerpanel.gd")
	var hud: String = FileAccess.get_file_as_string("res://src/ui/characterhud.gd")
	var spot: String = FileAccess.get_file_as_string("res://src/shared/safespot.gd")
	check("the three files are readable",
		panel.length() > 0 and hud.length() > 0 and spot.length() > 0)

	# SOMETHING ISSUES ONE NOW. This is the whole gap that was there.
	check("the panel posts to /api/staff/teleport",
		panel.contains("\"/api/staff/teleport\""),
		"the route and the landing both existed; nothing ever asked")
	for action in ["\"bring\"", "\"goto\"", "\"everyone\""]:
		check("the panel binds %s" % action, panel.contains(".bind(%s)" % action),
			"three buttons, three actions, one handler")

	# BESIDE, NOT ON. start_ring 1 is what "never the anchor itself" means, and
	# an anchor of body.global_position is what makes it "beside ME".
	check("a teleport here asks for a spot beside the issuer",
		panel.contains("SafeSpot.find(body, body.global_position, 1)"),
		"start_ring 0 would put somebody inside whoever pressed the button")
	# NOT "beside them" - the server has no position to land beside. saves holds
	# the AREA and nothing finer, which is why this button says "Go to area".
	# An earlier version read x/y off /api/staff/user, and those columns do not
	# exist: the request broke that route outright and test_security.py caught
	# it. This check pins the honest version so the claim cannot come back
	# without the positions that would make it true.
	check("going to a player travels to their area, and says so",
		panel.contains("The server does not")
			and panel.contains("AreaRegistry.go_to(area)"),
		"there is no position on the server to stand beside")

	# GOING SOMEWHERE IS LOCAL. Position is client-written, so asking the server
	# for permission to move yourself would be theatre - and can_act_on() is
	# strictly-greater, so the route would refuse acting on yourself anyway.
	var goto_at: int = panel.find("func _teleport_go_to_them(")
	check("going to a player moves you locally", goto_at != -1
		and panel.find("AreaRegistry.go_to(area)", goto_at) != -1,
		"a request to move yourself would be refused by can_act_on anyway")
	# COMMENTS STRIPPED, AND BOUNDED TO THE FUNCTION. This went red first on
	# correct code, for the reason the entry in CLAUDE.md now describes: the
	# comment inside _teleport_go_to_them() explaining why it does NOT post
	# names the route it does not post to.
	var goto_end: int = panel.find("\nfunc ", goto_at + 8)
	var posts_at: int = _first_code_index(panel, "/api/staff/teleport", goto_at)
	check("...and posts no teleport order for it",
		posts_at == -1 or (goto_end != -1 and posts_at > goto_end),
		"nobody else is being moved, so nothing should be queued for anybody")

	# THE RECEIVE PATH IS THE ONE THAT PROTECTS EVERY PLAYER, not just this panel.
	check("an arriving teleport is checked against the map",
		hud.contains("SafeSpot.find(body, spot, 0)"),
		"the server chose those coordinates knowing nothing about walls")
	check("...trying the server's own spot first",
		hud.contains(", spot, 0)"),
		"start_ring 1 would move a correctly-spaced group off its arrangement")
	check("...and going anyway if nothing is clear",
		hud.contains("landing = spot"),
		"refusing would strand somebody being moved OUT of a bad place")

	# THE HELPER'S OWN CONTRACT.
	check("SafeSpot refuses rather than inventing a spot",
		spot.contains("return Vector2.INF"),
		"landing outside the map is worse than not moving")
	check("it mirrors the server's spacing", spot.contains("const SPACING := 48.0"),
		"TELEPORT_SPACING in app.py is 48.0 - these are kept in step by hand")
	check("it tests the floor AND the walls",
		spot.contains("_on_navigable_ground(") and spot.contains("_nothing_in_the_way("),
		"navigation answers 'off the map'; physics answers 'in a wall'")
	check("and a scene with no navmesh is not refused outright",
		spot.contains("NavigationServer2D.map_get_regions(map).is_empty()"),
		"elusion.tscn has no NavigationRegion2D; town would fail every check")
	check("the shape query excludes the body itself",
		spot.contains("query.exclude = [body.get_rid()]"),
		"a character collides with its own position, so nowhere would read clear")
	check("and uses the body's own mask rather than a typed number",
		spot.contains("query.collision_mask = body.collision_mask"),
		"a layer added later would not reach a number written here")

	# THE ARMING. "Move everyone" broadcasts to the whole server.
	check("moving everyone is armed before it fires",
		panel.contains("_armed_action != \"everyone\""),
		"the widest button on the panel, one press from a typo")
	check("and _button_for knows it, so it disarms",
		panel.contains("return tp_everyone_button"),
		"without the entry the button reads Confirm? for ever after a timeout")

	print("  server spaces the group, the client keeps it out of the walls")


# =============================================================================
# THE PLAYERS MENU, AND THE PVP SWITCH THAT DOES NOT LIE
# =============================================================================
# A list anyone can open of who is playing, and an owner switch that announces
# hostility. The second one is the interesting half, because it is a control for
# something that DOES NOT EXIST YET: nothing in this game can damage another
# player - no positions on the server, no remote bodies in the client.
#
# That makes it precisely the shape of the bug this project spent a day removing:
# api.gd's comment saying characterhud.gd answered a signal that nothing was
# connected to. A switch labelled "PvP" that implied combat would be the same
# lie with a nicer font.
#
# So the rule for this feature is that EVERY PLACE IT SPEAKS SAYS WHAT IT IS.
# The button's tooltip, the panel's banner and the route's own response all state
# that nothing is damageable yet, and these checks hold them to it.
func _test_players_menu_and_pvp_are_honest() -> void:
	section("PLAYERS & PVP — a list anyone can read, and a switch that admits what it is")

	var panel: String = FileAccess.get_file_as_string("res://src/ui/players/playerspanel.gd")
	var scene: String = FileAccess.get_file_as_string("res://scene/ui/players/playerspanel.tscn")
	var hud: String = FileAccess.get_file_as_string("res://src/ui/characterhud.gd")
	var owner_panel: String = FileAccess.get_file_as_string("res://src/ui/owner/ownerpanel.gd")
	var owner_scene: String = FileAccess.get_file_as_string("res://scene/ui/owner/ownerpanel.tscn")
	check("every file is readable",
		panel.length() > 0 and scene.length() > 0 and owner_panel.length() > 0)

	# ANYONE CAN OPEN IT. A button on the nav row, not behind a rank.
	check("the HUD has a Players button", hud.contains("\"playersbutton\""),
		"a menu nobody can open is not a menu")
	check("and it builds the panel on first use, like every other one",
		hud.contains("PLAYERS_PANEL_SCENE.instantiate()"),
		"a panel instantiated at spawn polls for a screen nobody asked for")
	check("the scene carries the rows container the script reads",
		scene.contains("name=\"playersrows\"") and panel.contains("%playersrows"),
		"a unique name the scene lacks is a null the panel silently skips")

	# THE WORDING FOLLOWS THE SERVER'S OWN precision FIELD rather than promising
	# a distance nobody measured - the same rule the trade panel already keeps.
	check("the heading reads the server's precision field",
		panel.contains("data.get(\"precision\", \"area\")"),
		"the server says how precise it is; assuming is how a lie ships")

	# ONLY WHILE OPEN, and never two reads at once.
	# SCOPED TO THE TIMER, because "if visible:" also appears in toggle() - so an
	# unscoped search passed a sabotage that removed the guard from the poll.
	# The same shape as every other text check here: a phrase that is true
	# somewhere else in the file is not evidence about the place that matters.
	var tick: int = panel.find("func _on_refresh_timeout(")
	var tick_end: int = panel.find("\nfunc ", tick + 8)
	var guard: int = _first_code_index(panel, "if visible:", tick)
	check("it only polls while open",
		tick != -1 and guard != -1 and (tick_end == -1 or guard < tick_end),
		"a closed panel polling every 15 seconds for a whole session")
	check("and never overlaps its own request", panel.contains("if _loading:"),
		"two replies out of order paint the older one last")
	check("it guards after the await", panel.contains("not is_inside_tree()"),
		"the panel can be closed, or the scene changed, while a request is out")

	# THE SWITCH. Server state, asked rather than remembered.
	check("the owner panel has a PvP switch", owner_scene.contains("name=\"pvpbutton\""))
	check("and it posts to the server rather than flipping a local flag",
		owner_panel.contains("\"/api/server/pvp\""),
		"a flag in a client is a flag an attacker sets")
	check("it reads the state back rather than remembering it",
		owner_panel.contains("func _refresh_pvp("),
		"the owner may have thrown it from another machine")
	check("mirrors without re-emitting",
		owner_panel.contains("pvp_button.set_pressed_no_signal("),
		"writing button_pressed fires toggled, which would post what it displays")
	check("and puts the switch back when the server refuses",
		owner_panel.contains("await _refresh_pvp()"),
		"a refused press must not leave the button claiming something untrue")

	# =========================================================================
	# EVERY ROW SITS ON A BOX, AND YOURS IS THE BRIGHT ONE
	# =========================================================================
	# BEHAVIOURAL, NOT TEXTUAL. _row() is pure node-building over a Dictionary
	# and touches none of the @onready vars, so the script can be instantiated
	# bare and asked - which is the only way to prove the box is actually AROUND
	# the row rather than beside it, and the only way the own-row test can be
	# fed a name and checked.
	var players_script: Script = load("res://src/ui/players/playerspanel.gd") as Script
	check("the players panel is readable without a server", players_script != null)
	if players_script != null:
		var bare: Control = players_script.new()
		var was_name: String = Api.username
		Api.username = "Tunacan"

		var stranger: Control = bare._row({
			"username": "Ahvassa", "name": "mage", "level": 12,
			"area": "field", "role": "player", "guild_tag": ""})

		check("a player row sits on a box", stranger is PanelContainer,
			stranger.get_class())

		# A VARIATION THE THEME DOES NOT DEFINE FALLS BACK TO THE PLAIN
		# PanelContainer STYLE, silently - so a renamed variation is a box that
		# is still there and no longer the right one. Checked against the theme
		# file rather than assumed.
		var theme_src: String = FileAccess.get_file_as_string(
			"res://assets/themes/rpg_ui_theme.tres")
		check("and the theme actually defines the variation it asks for",
			theme_src.contains("%s/styles/panel" % players_script.ROW_BOX)
				and theme_src.contains("%s/styles/panel" % players_script.OWN_ROW_BOX),
			"%s / %s" % [players_script.ROW_BOX, players_script.OWN_ROW_BOX])
		check("somebody else's row wears the subtle one",
			stranger.theme_type_variation == players_script.ROW_BOX,
			stranger.theme_type_variation)

		# THE ROW ITSELF MUST SURVIVE THE WRAPPING. A box with the content
		# dropped on the floor is a tidy empty box, and it would pass every
		# check above.
		check("the name is still in there after being boxed",
			_labels_under(stranger).find("Ahvassa  (mage)") != -1,
			_labels_under(stranger))

		var mine: Control = bare._row({
			"username": "tunacan", "name": "warrior", "level": 29,
			"area": "elusion", "role": "owner", "guild_tag": ""})
		check("your own row wears the bright one",
			mine.theme_type_variation == players_script.OWN_ROW_BOX,
			mine.theme_type_variation)
		# LOWERCASE ON PURPOSE ABOVE: the users table is COLLATE NOCASE, so the
		# server treats Tunacan and tunacan as one account. A case-sensitive
		# test would fail to find you in your own list depending on how you
		# happened to type it at the login screen.
		check("and the two boxes are not the same box",
			players_script.ROW_BOX != players_script.OWN_ROW_BOX,
			"one variation for both is no highlight at all")

		# THE ACCOUNT NAME, NOT THE CHARACTER NAME. One account has several
		# characters and nothing stops two accounts naming a character the same
		# thing, so matching on `name` puts the bright box on a stranger.
		var impostor: Control = bare._row({
			"username": "SomebodyElse", "name": "Tunacan", "level": 3,
			"area": "field", "role": "player", "guild_tag": ""})
		check("a stranger whose CHARACTER shares your account name is not you",
			impostor.theme_type_variation == players_script.ROW_BOX,
			impostor.theme_type_variation)

		# SIGNED OUT MATCHES NOBODY. Api.username is "" before login and after
		# sign-out, and "" == "" against an absent username would put the bright
		# box on whichever row happened to be missing one.
		Api.username = ""
		var nameless: Control = bare._row({
			"username": "", "name": "warrior", "level": 1,
			"area": "elusion", "role": "player", "guild_tag": ""})
		check("with nobody signed in, no row is yours",
			nameless.theme_type_variation == players_script.ROW_BOX,
			nameless.theme_type_variation)

		Api.username = was_name
		stranger.free()
		mine.free()
		impostor.free()
		nameless.free()
		bare.free()

	# THE HONESTY, which is the whole point of this section.
	check("the panel's banner says nobody can be damaged yet",
		panel.contains("Nobody can damage anybody"),
		"a PvP banner implying combat is a comment describing a wire nobody ran")
	check("and the switch's tooltip says it too",
		owner_scene.contains("does NOT make anybody damageable"),
		"the tooltip is where somebody reads what the button will do")

	print("  a switch for combat that does not exist, and it says so everywhere")


# =============================================================================
# A DEATH HAS TO REACH THE SERVER
# =============================================================================
# The kingdom board counts deaths and they were never going up, and the server
# was not the problem: PUT /api/player/status counts a death on the TRANSITION
# from stored hp above zero to an arriving hp at or below it, and test_economy.py
# already covers it three ways - "a death is counted", "staying dead is not five
# more deaths", "healing up does not count as anything".
#
# THE ZERO SIMPLY NEVER ARRIVED. take_damage() ends by calling gain_defense_xp(),
# which is the only call on that path reaching CharacterData - and on the fatal
# hit it returns two lines earlier at `if hp <= 0`. So the one hit that mattered
# was the one hit that never saved, and by the time anything else did the player
# had revived or left, both with a healthy number.
#
# The same shape as half the bugs found in this project: a server half that was
# right and tested, and a client half nobody had wired to it.
func _test_death_reaches_the_server() -> void:
	section("DEATH — the fatal hit is the one that has to be saved")

	var src: String = FileAccess.get_file_as_string("res://src/characters/player.gd")
	check("player.gd is readable", src.length() > 0)

	var seq: int = src.find("func _start_death_sequence(")
	check("there is a death sequence", seq != -1)
	if seq == -1:
		return

	# COMMENTS STRIPPED. The block explaining this fix names every symbol these
	# checks look for - _change_to_game_over, gain_defense_xp, flush_save - so a
	# plain find() would be reading the explanation rather than the code.
	# BOUNDED TO THE FUNCTION, and the first version was not - which a sabotage
	# proved by removing the save and leaving this check green.
	# save_character_state() is called from four other places in this file, all
	# of them BELOW _start_death_sequence(), so a search that ran to the end of
	# the file found one of those and reported the death path as saving.
	#
	# The third time bounding has been needed here. _first_code_index() answers
	# "where is this in code rather than in a comment"; it does not answer
	# "inside which function", and a search for something common needs both.
	var seq_end: int = src.find("\nfunc ", seq + 8)
	var saved: int = _within(_first_code_index(src, "CharacterData.save_character_state(self)", seq), seq_end)
	var flushed: int = _within(_first_code_index(src, "CharacterData.flush_save()", seq), seq_end)
	check("the death sequence saves the character", saved != -1,
		"the fatal hit returns before gain_defense_xp, which is what saves")
	check("and FLUSHES it rather than queueing it", flushed != -1,
		"save_data() writes on a later frame, and the scene change means there "
		+ "is no later frame")

	# ORDER. The scene change is what frees this node; a save after it is a save
	# that never happens.
	var gone: int = _within(_first_code_index(src, "_change_to_game_over", seq), seq_end)
	check("both happen before the scene change",
		saved != -1 and flushed != -1 and gone != -1 and saved < gone and flushed < gone,
		"change_scene_to_file replaces the scene; anything after it is gone")

	# THE AWAIT TRAP, which this project has a measured table for. This node is
	# about to be freed, and Godot silently DROPS a coroutine whose object is
	# gone - so the waiting must be done by the autoload, not by the player.
	var line_start: int = src.rfind("\n", flushed) + 1
	var flush_line: String = src.substr(line_start, flushed - line_start + 32)
	check("and the flush is not awaited from the dying node",
		not flush_line.contains("await"),
		"a coroutine owned by a node that is being freed is dropped silently")

	# THE SAVE HAS TO CARRY hp, or it is a write with nothing in it.
	var data: String = FileAccess.get_file_as_string("res://src/systems/characterdata.gd")
	check("hp is one of the saved stats", data.contains("\"hp\":"),
		"the zero is the whole message; a save without it says nothing")
	check("and save_character_state still queues a save",
		data.contains("save_data()"),
		"flush_save() only writes when something is pending")

	# =========================================================================
	# AND THE OTHER WAY OUT OF THE DEATH SCREEN
	# =========================================================================
	# The screen has two exits. /api/character/revive was migrated to the
	# server under a comment beginning "THE SERVER DOES ALL THREE THINGS THAT
	# USED TO HAPPEN HERE" - and the button beside it went on writing full hp
	# into the save slot itself.
	#
	# It produced a character on 52 hp. The client healed itself to 504, the
	# next status push read as a rise from zero with nothing authorising it,
	# and _reconcile_heals() clamped it to what a few seconds of regeneration
	# could produce. Full bars on screen, a corpse after a relog.
	var over: String = FileAccess.get_file_as_string("res://src/ui/menus/gameover.gd")
	check("gameover.gd is readable", over.length() > 0)

	var ret: int = over.find("func _on_return_pressed(")
	var ret_end: int = over.find("\nfunc ", ret + 8)
	check("the return path exists", ret != -1)
	check("and it asks the server to respawn",
		_within(_first_code_index(over, "/api/character/respawn", ret), ret_end) != -1,
		"accepting death is a fact; full health and an empty purse are decisions")

	# THE CHECK THAT WOULD HAVE CAUGHT IT. Not "does it call the route" - a
	# version that calls the route AND still writes its own hp is the same bug
	# with a network request in front of it.
	var clear_at: int = over.find("func _clear_carry_on_death(")
	var clear_end: int = over.find("\nfunc ", clear_at + 8)
	check("and nothing on that path writes its own hp",
		_within(_first_code_index(over, "slot_data[\"hp\"]", ret), ret_end) == -1
			and _within(_first_code_index(over, "slot_data[\"hp\"]", clear_at), clear_end) == -1,
		"the client deciding its own health is exactly what the reconciler clamped")

	# A FAILED REQUEST MUST NOT FALL BACK TO THE LOCAL RESTORE, because the
	# local restore IS the bug. Better to leave the player on the death screen
	# with a reason than to put them back where the clamp will find them.
	check("a refusal is reported rather than worked around",
		_within(_first_code_index(over, "_restore_character_resources(", ret), ret_end) == -1,
		"falling back locally reintroduces the unauthorised heal")

	# A PAID REVIVE LANDS IN TOWN, decided on day 1. It always did; what was
	# wrong was a GameState.reviving flag and three comments promising a
	# return to death_position that nothing ever read.
	var screen: Node = (load("res://src/ui/menus/gameover.gd") as Script).new()
	check("a revive goes to the town, where every login starts",
		str(screen.get("world_scene_path")) == "res://scene/elusion.tscn", screen.get("world_scene_path"))
	screen.free()
	check("  and no flag pretends it goes back to where you died",
		not ("reviving" in GameState) and over.find("GameState.reviving =") == -1)

	# A FULL DEATH TAKES WHAT IS WORN TOO (day 2, the owner's call), and the
	# local copy follows the server: no gear, and a bag base that says the
	# server's bag is empty. Without the base, the first save after every full
	# death was refused as stale and logged "inventory:0 rejected".
	var slots_were: Array = CharacterData.character_slots
	var failed_was: bool = CharacterData.load_failed
	CharacterData.load_failed = true      # save_data() refuses: nothing leaves the suite
	CharacterData.character_slots = [{"character": "suitecorpse", "gold": 75,
		"inventory": [{"item_id": "tinyhealthpotion", "quantity": 3}],
		"equipment": {"weapon": "doubleaxe", "amulet": "exaltedvitalityamulet"}},
		null, null, null]     # always four: _ensure_slot_array() resets any other shape
	var mourner: Node = (load("res://src/ui/menus/gameover.gd") as Script).new()
	mourner._clear_carry_on_death("suitecorpse")
	var corpse: Dictionary = CharacterData.get_character_by_name("suitecorpse")
	check("accepting death takes the bag, the purse and everything worn",
		corpse.get("inventory") == [] and int(corpse.get("gold", -1)) == 0 and corpse.get("equipment") == {},
		[corpse.get("inventory"), corpse.get("gold"), corpse.get("equipment")])
	mourner.free()
	CharacterData.character_slots = slots_were
	CharacterData.load_failed = failed_was

	var over_scene: Node = (load("res://scene/ui/menus/gameover.tscn") as PackedScene).instantiate()
	var give_up: Button = over_scene.get_node_or_null("%returnbutton") as Button
	check("the button says what it costs before it is pressed",
		give_up != null and give_up.tooltip_text.contains("everything you are wearing")
		and give_up.tooltip_text.contains("bank is safe"), give_up.tooltip_text if give_up else "no button")
	over_scene.free()

	print("  the server counted transitions correctly all along")


# =============================================================================
# A PLAYER HAS TO BE TOLD WHAT IS TRUE RIGHT NOW
# =============================================================================
# The HUD had one surface for everything the world said, and it treated an EVENT
# and a STATE identically - four "has gone hostile" lines sitting there for ever
# with no timestamps. app.py makes the same distinction about deaths and gets it
# right: "A death is a TRANSITION, NOT A STATE, and counting it as a state is
# the bug worth not writing."
#
# So there are two surfaces now. The message box keeps events, which are history
# and belong in chat. The status strip carries states, which are true now, must
# not scroll away, and must vanish the moment they stop being true.
#
# THE ONE THAT MATTERS IS THE CONNECTION. heartbeat_verdict() has returned three
# values all along - ok, revoked, offline - and the broadcast poll threw the
# third away with a bare `return`. So a client that could not reach the server
# went on playing with nothing on screen to say so, and everything since the
# last successful save was lost without a word. The answer existed; nothing
# acted on it. The fourth time that exact shape has turned up in this project.
func _test_world_status_is_shown() -> void:
	section("STATUS STRIP — what is true now, separate from what happened")

	var hud: String = FileAccess.get_file_as_string("res://src/ui/characterhud.gd")
	check("characterhud.gd is readable", hud.length() > 0)

	check("there is a strip, built beside the message box",
		hud.contains("func _build_status_strip(") and hud.contains("_build_status_strip()"),
		"a builder nothing calls is a panel nobody sees")
	check("and it never eats a click",
		_within(_first_code_index(hud, "MOUSE_FILTER_IGNORE",
			hud.find("func _build_status_strip(")),
			hud.find("\nfunc ", hud.find("func _build_status_strip(") + 8)) != -1,
		"it sits over the play area; swallowing input would kill the world under it")

	# STATES ARE KEYED AND CLEARABLE. A strip that can only be set is a strip
	# that lies as soon as the thing it announced stops being true.
	check("states are set by key", hud.contains("func set_world_status(key: String"))
	check("and an empty text clears one", hud.contains("_status_states.erase(key)"),
		"otherwise a reopened server keeps its closing warning on screen")
	check("one line at a time, by priority", hud.contains("const STATUS_PRIORITY :="),
		"two stacked warnings is how neither gets read")

	# THE OFFLINE VERDICT IS FINALLY ACTED ON.
	check("a good verdict records contact", hud.contains("func _note_server_contact("))
	# BOTH CALL SITES, EACH BY NAME. Counting occurrences was the first version
	# and it was wrong twice over: `func _note_server_contact() -> void:`
	# contains the string too, so the definition counted as a call, and removing
	# one of the two real calls still left the total at two. A count is not
	# evidence about a place.
	for caller in ["_on_broadcast_poll_timeout", "_on_unauthorized_seen"]:
		var at: int = hud.find("func %s(" % caller)
		var at_end: int = hud.find("\nfunc ", at + 8)
		check("%s() records contact" % caller,
			at != -1 and _within(_first_code_index(hud, "_note_server_contact()", at), at_end) != -1,
			"both polls answer the same question; only counting one leaves a gap")
	check("the countdown runs every frame, not on a timer",
		hud.contains("_tick_connection_status()") and hud.contains("func _process("),
		"a countdown that updates every ten seconds does not read as a countdown")
	check("it waits out a grace before crying wolf",
		hud.contains("const OFFLINE_GRACE_SECONDS :="),
		"one missed poll is ordinary; announcing it makes the strip flicker")
	check("and it eventually gives up rather than pretending",
		hud.contains("const OFFLINE_SIGNOUT_SECONDS :="),
		"playing on into a lost session loses everything since the last save")
	check("the reason travels to the login screen",
		hud.contains("Lost connection to the server."),
		"a silent return to the menu gets reported as a crash")

	# RECOVERY IS AS AUTOMATIC AS THE WARNING.
	# SCOPED TO _note_server_contact(). set_world_status("connection", "") also
	# appears in the give-up path and in the not-logged-in branch, so an
	# unscoped search is evidence about the wrong function - which a sabotage
	# proved by removing the recovery and leaving this green.
	var contact: int = hud.find("func _note_server_contact(")
	var contact_end: int = hud.find("\nfunc ", contact + 8)
	check("reconnecting clears the warning",
		_within(_first_code_index(hud, "set_world_status(\"connection\", \"\")", contact),
			contact_end) != -1,
		"a player who reconnects should not be left reading a stale alarm")

	# THE MAINTENANCE NOTICE IS A STATE, WHICH MEANS THE STRIP HAS TO BE PAINTED
	# ABOVE THE ONCE-ONLY GUARD.
	#
	# THE CHECK THAT USED TO BE HERE WAS ITSELF THE BUG, and it is the cleanest
	# example this suite has of the trap the file above keeps warning about. It
	# was named "the closing server counts down on the strip" and its body asked
	# whether the substring set_world_status("maintenance", appeared ANYWHERE in
	# the file. It did - three lines BELOW `if _maintenance_warned: return`, so
	# it ran on exactly one poll and the number never moved once. The comment
	# beside it in characterhud.gd said "Re-set on every poll, so the number
	# counts down for real", and that was false too.
	#
	# So: a check named after a behaviour, a comment describing that behaviour,
	# and code doing the opposite - and the only thing that could ever have told
	# them apart is ORDER. It is checked by index for that reason, the same way
	# _test_god_mode_earns_nothing() checks its guard.
	var read_at: int = hud.find("func _read_maintenance(")
	var read_end: int = hud.find("\nfunc ", read_at + 8)
	var strip_at: int = _within(_first_code_index(
		hud, "set_world_status(\"maintenance\", _maintenance_line", read_at), read_end)
	var guard_at: int = _within(_first_code_index(
		hud, "if _maintenance_warned:", read_at), read_end)
	check("the countdown is painted BEFORE the once-only guard",
		strip_at != -1 and guard_at != -1 and strip_at < guard_at,
		"strip %d, guard %d - below the guard it paints once and freezes there"
			% [strip_at, guard_at])
	check("and reopening takes it down",
		hud.contains("set_world_status(\"maintenance\", \"\")"))

	# WHAT THE STRIP ACTUALLY SAYS, asked directly. _maintenance_line() is
	# static and pure apart from Api.is_owner, so the three states can be read
	# off rather than inferred from a substring - which is what let the old
	# check pass on frozen code.
	var hud_script: Script = load("res://src/ui/characterhud.gd") as Script
	check("the HUD's closing wording is readable without a server", hud_script != null)
	if hud_script != null:
		var was_owner: bool = Api.is_owner
		Api.is_owner = false

		check("while the window is open it says how long and that saving is on",
			str(hud_script._maintenance_line(125))
				== "Server closes in 2:05 - your progress is being saved",
			hud_script._maintenance_line(125))

		# ZERO IS A DIFFERENT STATE, NOT A SMALLER NUMBER. This is the exact
		# line that shipped: log in after the window is spent and the first poll
		# reads seconds_left 0, so the strip read "Server closes in 0:00 - your
		# progress is being saved" and stayed there. Both halves are false at
		# once - it is not closing, it has closed, and nothing is being saved.
		var spent: String = str(hud_script._maintenance_line(0))
		check("spent, it stops promising a save that is already over",
			not spent.contains("being saved"), spent)
		check("and stops counting down to something already done",
			not spent.contains("0:00"), spent)
		check("a player is told the session is ending",
			spent.contains("signed out"), spent)

		# THE OWNER IS EXEMPT BY NAME on the server - maintenance_refusal() and
		# maintenance_disconnect() both skip them so nobody can lock themselves
		# out of their own server. The cost is that throwing the switch looks
		# like it did nothing from the one chair that threw it.
		Api.is_owner = true
		var owner_line: String = str(hud_script._maintenance_line(0))
		var owner_open: String = str(hud_script._maintenance_line(125))
		Api.is_owner = was_owner

		check("the owner is told they are the exception",
			owner_line.contains("exempt"), owner_line)
		check("and that it is the PLAYERS who are shut out",
			owner_line.contains("CLOSED to players"), owner_line)
		check("which is not what a player reads", owner_line != spent,
			"one line for two situations is the switch looking broken")
		# AND THE CLAIM ITSELF, not just that the two strings differ. Sabotage
		# found this gap: adding "(exempt)" to the PLAYER's line left the two
		# readings unequal, so the check above stayed green while the client
		# told a player about to be signed out that they were exempt. Inequality
		# is a weaker claim than it looks - it is satisfied by any difference,
		# including the wrong one.
		check("and a player is never told they are exempt when they are not",
			not spent.to_lower().contains("exempt"), spent)
		check("but while the window is open there is one line for everybody",
			owner_open == "Server closes in 2:05 - your progress is being saved",
			owner_open)

		# THE CHAT LINE IS AN EVENT AND MUST NOT COUNT DOWN TO ZERO EITHER.
		# "The server is closing in 0s. Saving your progress now." was landing
		# in the log of players who arrived long after it happened, stamped as
		# news, because it was built from the same frozen number.
		check("the chat notice does not announce a countdown of zero",
			not str(hud_script._maintenance_announcement(0)).contains("in 0s"),
			hud_script._maintenance_announcement(0))
		check("and still counts down while there is something to count",
			str(hud_script._maintenance_announcement(90)).contains("90"),
			hud_script._maintenance_announcement(90))

	# PVP RIDES THE SAME POLL.
	check("PvP shows for somebody who logged in after the announcement",
		hud.contains("set_world_status(\"pvp\","),
		"a broadcast only reaches the people who were already there")

	# THE BAN, WHICH IS THE ONE COUNTDOWN THAT DOES NOT TICK.
	var login: String = FileAccess.get_file_as_string("res://src/ui/menus/loginmenu.gd")
	check("a ban says how long is left, not only the date",
		login.contains("func describe_ban_remaining(") and login.contains("left)"),
		"a date makes somebody count on their fingers")

	# Pure and static, so it can be asked directly rather than inferred.
	var menu: Script = load("res://src/ui/menus/loginmenu.gd") as Script
	check("the ban wording is readable without a server", menu != null)
	if menu != null:
		check("a ban that has run out says nothing",
			str(menu.describe_ban_remaining(0)) == ""
				and str(menu.describe_ban_remaining(-50)) == "",
			"counting down a ban the next login will simply ignore")
		check("days and hours read as days and hours",
			str(menu.describe_ban_remaining(86400 * 2 + 3600 * 4)) == "2 days, 4 hours",
			menu.describe_ban_remaining(86400 * 2 + 3600 * 4))
		check("one day is not 1 days",
			str(menu.describe_ban_remaining(86400 + 60)) == "1 day",
			menu.describe_ban_remaining(86400 + 60))
		check("under an hour never reads as zero",
			str(menu.describe_ban_remaining(40)) != "0 minutes"
				and str(menu.describe_ban_remaining(40)) != "",
			menu.describe_ban_remaining(40))

	print("  events scroll away, states do not")


func _test_timestamps_are_the_servers() -> void:
	section("TIMESTAMPS — when a thing happened, not when you read about it")

	# =========================================================================
	# ONE CONVERSION, IN ONE PLACE
	# =========================================================================
	# There were four copies of "unix seconds plus the system bias, then
	# decompose" in this project. The fourth, in ownerpanel.gd, had lost the
	# bias and was printing UTC under no label at all - seven hours out in
	# Denver, thirteen in Sydney, and wrong in the way that looks like right.

	check("LocalTime exists", LocalTime.bias_minutes() == LocalTime.bias_minutes(),
		"the bias must be stable within a run or every stamp disagrees with the last")

	check("an unrecorded time says so rather than showing the epoch",
		LocalTime.stamp(0) == "--:--" and LocalTime.stamp(-5) == "--:--",
		LocalTime.stamp(0))
	check("and full() agrees with it", LocalTime.full(0) == "--:--", LocalTime.full(0))

	# THE SHIFT IS APPLIED, AND EXACTLY ONCE. Compared against Godot's own UTC
	# decomposition rather than against a hardcoded hour, so this check means
	# the same thing on his machine in MST as it does on a build server in UTC.
	var moment: int = int(Time.get_unix_time_from_datetime_dict({
		"year": 2026, "month": 6, "day": 15, "hour": 12, "minute": 0, "second": 0}))
	var utc: Dictionary = Time.get_datetime_dict_from_unix_time(moment)
	var local: Dictionary = LocalTime.parts(moment)
	var shifted: int = (int(local["hour"]) * 60 + int(local["minute"])) \
		- (int(utc["hour"]) * 60 + int(utc["minute"]))
	while shifted <= -720:
		shifted += 1440
	while shifted > 720:
		shifted -= 1440
	check("the local clock is the UTC clock plus the system offset",
		shifted == LocalTime.bias_minutes(),
		"%d vs %d" % [shifted, LocalTime.bias_minutes()])

	# =========================================================================
	# A BARE CLOCK IS ONLY TRUE FOR TODAY
	# =========================================================================
	# The first poll after login asks since=0, and the server answers with the
	# TAIL of the broadcast table - up to a week of notices at once. Stamped
	# "14:32" apiece they read as a week of things happening now, which is
	# worse than no stamp: it does not fail to inform, it misinforms.
	var now: int = int(Time.get_unix_time_from_system())
	# "MINUTES AGO" STAYS ON TODAY. Five minutes back from 00:03 is yesterday,
	# and the stamp rightly says so - which made this check fail for the first
	# five minutes of every day. Found at 00:04 on 30 September.
	var today_parts: Dictionary = LocalTime.parts(now)
	var since_midnight: int = int(today_parts["hour"]) * 3600 + int(today_parts["minute"]) * 60 \
		+ int(today_parts.get("second", 0))
	var minutes_ago: int = now - mini(300, since_midnight)
	check("something from minutes ago is just a clock",
		LocalTime.stamp(minutes_ago) == LocalTime.clock(minutes_ago),
		LocalTime.stamp(minutes_ago))
	check("something from three days ago carries the weekday",
		LocalTime.WEEKDAYS.has(LocalTime.stamp(now - 3 * 86400).substr(0, 3)),
		LocalTime.stamp(now - 3 * 86400))
	# SIX DAYS, NOT SEVEN. At seven, "Sat" means either this Saturday or the
	# one before it - the exact ambiguity a date is here to remove.
	check("six days back is still a weekday",
		LocalTime.WEEKDAYS.has(LocalTime.stamp(now - 6 * 86400 + 3600).substr(0, 3)),
		LocalTime.stamp(now - 6 * 86400 + 3600))
	check("seven days back is a date instead",
		not LocalTime.WEEKDAYS.has(LocalTime.stamp(now - 7 * 86400 - 3600).substr(0, 3)),
		LocalTime.stamp(now - 7 * 86400 - 3600))
	check("and a month back names the month",
		LocalTime.stamp(now - 30 * 86400).substr(0, 3)
			== LocalTime.MONTHS[int(LocalTime.parts(now - 30 * 86400)["month"])],
		LocalTime.stamp(now - 30 * 86400))

	# =========================================================================
	# THE SERVER NOTICE, WHICH IS THE ONE THAT HAD NO TIME AT ALL
	# =========================================================================
	var chat: Node = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	add_child(chat)

	# A KNOWN, OLD TIMESTAMP. Using "now" here would let a client that ignores
	# the argument and stamps with its own clock pass every check below.
	var sent: int = now - (2 * 86400) - 7200
	chat.push_system_line("Tunacan has gone hostile.", Color(1, 1, 1), sent)
	var lines: Array = chat._feeds["world"]["lines"]
	check("a server notice lands in the world channel", lines.size() == 1, lines.size())
	check("and keeps the moment it was SENT, not the moment it was shown",
		lines.size() == 1 and int(lines[-1].get("at", 0)) == sent,
		lines[-1].get("at", 0) if lines.size() == 1 else "no line")

	# THE RENDERED LINE, not the dictionary behind it. The dictionary carrying
	# an `at` is worth nothing if the branch that draws it returns before the
	# stamp is used - which is exactly what kind == "system" did.
	var drawn: Control = chat._node_for(lines[-1])
	var shown: String = ""
	if drawn is RichTextLabel:
		shown = (drawn as RichTextLabel).get_parsed_text()
	check("the notice is drawn with its stamp on it",
		shown.contains(LocalTime.stamp(sent)),
		"%s (wanted %s)" % [shown, LocalTime.stamp(sent)])
	check("and it is still marked as the server speaking",
		shown.contains("[SERVER]"), shown)
	# HELD IN A VARIABLE SO IT CAN BE FREED. The first version compared the
	# result of _node_for() inline, which built a RichTextLabel nobody owned -
	# and a RichTextLabel is three font RIDs and a shaped-text buffer, so the
	# run ended with "resources still in use at exit". A leak in a test is
	# still a leak, and it hides the next one.
	var player_line: Control = chat._node_for({"kind": "chat", "by": "someone",
		"role": "player", "body": "hi", "at": sent})
	check("a player line is stamped the same way",
		String((player_line as RichTextLabel).get_parsed_text()).contains(
			LocalTime.stamp(sent)),
		(player_line as RichTextLabel).get_parsed_text())
	player_line.free()
	drawn.free()

	# NO TIMESTAMP MEANS NOW, and only for a line this client invented about
	# itself - there is no server row behind one, so there is nothing to read.
	chat.push_system_line("Lost connection.", Color(1, 1, 1))
	check("a notice this client made up is stamped now",
		absi(int(chat._feeds["world"]["lines"][-1].get("at", 0)) - now) <= 5,
		chat._feeds["world"]["lines"][-1].get("at", 0))
	chat.free()

	# =========================================================================
	# THE PATH TO THE BUTTON, WHICH IS WHERE THE BUG ACTUALLY WAS
	# =========================================================================
	# push_system_line() taking an `at` proves nothing on its own: the defect
	# was that the poll handler never passed one. chatpanel.gd's own comment
	# about the delete button says it - the button was tested, the path to the
	# button was not - so this reads the loop that feeds it.
	var hud: String = FileAccess.get_file_as_string("res://src/ui/characterhud.gd")
	var loop: int = hud.find("func _read_broadcast_messages(")
	var loop_end: int = hud.find("\nfunc ", loop + 8)
	check("the broadcast loop is a function with a name",
		loop != -1, "six lines inside a poll handler cannot be called, so cannot be tested")
	check("and it reads the server's at off each entry",
		_within(_first_code_index(hud, "entry.get(\"at\"", loop), loop_end) != -1,
		"without this every notice is stamped with the reader's arrival time")
	check("_push_message carries a timestamp through",
		hud.contains("func _push_message(text: String, color: Color, at: int = 0"),
		"the argument has to survive the hop or the loop above is decorative")

	# THE RECORD IS WRITTEN EVEN WHEN NOBODY IS LOOKING. The old code sent the
	# notice to the chat log OR the fading box, never both, so a player with
	# chat closed got a few seconds of it and no trace afterwards - which is
	# the whole complaint: log in, see nothing, have no idea.
	var push: int = hud.find("func _push_message(")
	var push_end: int = hud.find("\nfunc ", push + 8)
	var writes_log: int = _within(_first_code_index(hud, "push_system_line(", push), push_end)
	var reads_visible: int = _within(_first_code_index(hud, ".visible", push), push_end)
	# ORDER, NOT PRESENCE, AND THAT DISTINCTION COST A SABOTAGE. The first
	# version of this check asked whether _push_message() calls
	# push_system_line() at all and whether it does so before it touches
	# message_rows - and the broken version did BOTH. It called the log, just
	# behind `if chat_panel.visible`, which is the entire bug. A check that
	# passes the thing it was written to catch is worse than no check.
	#
	# So: the log write must come before this function has looked at whether
	# anything is visible. A record that is conditional on somebody already
	# looking is not a record.
	check("the log is written before anything asks what is on screen",
		writes_log != -1 and (reads_visible == -1 or writes_log < reads_visible),
		"log at %d, first visibility test at %d - a notice that only ever went to a fading box is one nobody can go back to"
			% [writes_log, reads_visible])

	# =========================================================================
	# PVP SAYS SINCE WHEN
	# =========================================================================
	var pvp: int = hud.find("func _read_pvp(")
	var pvp_end: int = hud.find("\nfunc ", pvp + 8)
	check("the pvp state is read by a named function too", pvp != -1)
	check("and it is told when the switch was thrown",
		_within(_first_code_index(hud, "pvp_at", pvp), pvp_end) != -1,
		"\"PvP is ON\" does not answer the question somebody who just arrived is asking")
	check("with the time rendered locally, not pasted in raw",
		_within(_first_code_index(hud, "LocalTime.stamp(", pvp), pvp_end) != -1)

	# =========================================================================
	# NO SECOND COPY OF THE CONVERSION
	# =========================================================================
	# This is the check that keeps the fifth copy from being written. Matching
	# on the CALL rather than on any comment, because this file's house style
	# means a comment about the timezone contains the timezone's own name.
	for path in ["res://src/ui/chat/chatpanel.gd", "res://src/ui/owner/ownerpanel.gd",
			"res://src/ui/staff/staffpanel.gd", "res://src/ui/menus/loginmenu.gd"]:
		var body: String = FileAccess.get_file_as_string(path)
		check("%s asks LocalTime rather than converting its own" % path.get_file(),
			_first_code_index(body, "Time.get_time_zone_from_system(", 0) == -1,
			"four copies is how ownerpanel.gd ended up printing UTC")

	print("  a timestamp made on receipt measures when the reader turned up")


# =============================================================================
# GIVEN AND LOST ARE DIFFERENT VERBS
# =============================================================================
# Death destroys the gold you were carrying, and the board counts every
# destroyed coin as a contribution - so a player who dies a lot climbs it
# without ever having decided to give anything. That rule is kept, because
# "contribution is every gold destroyed" is the board's whole claim and
# carving an exception into it would make the total stop adding up.
#
# What is NOT kept is the flattery. A ranking whose top entry is mostly deaths
# says something different from one whose top entry is mostly spending, and the
# panel has to be able to tell a reader which it is looking at.
func _test_board_says_what_it_is_made_of() -> void:
	section("THE COFFERS — given and lost are different verbs")

	var scene: PackedScene = load("res://scene/ui/kingdom/kingdomboard.tscn")
	check("the board scene loads", scene != null)
	if scene == null:
		return
	var board: Control = scene.instantiate()
	add_child(board)

	# ---- your own line ------------------------------------------------------
	var plain: String = board._your_line({"contributed": 900, "lusions": 0,
		"lost": 0, "rank": 1}, 1)
	check("somebody who has never died is not told about losses",
		not plain.to_lower().contains("lost"), plain)

	var bereaved: String = board._your_line({"contributed": 900, "lusions": 0,
		"lost": 400, "rank": 1}, 1)
	check("and somebody who has is told how much of it was not a gift",
		bereaved.to_lower().contains("lost"), bereaved)
	check("with the figure in it, not just the word",
		bereaved.contains("400"), bereaved)
	# THE WHOLE CONTRIBUTION MUST STILL BE THERE. The point is to qualify the
	# number, not to quietly subtract from it - a line that showed 500 would be
	# a second, disagreeing answer to "what have I given".
	check("and the contribution itself is unchanged",
		bereaved.contains("900"), bereaved)

	# ---- a row on the list --------------------------------------------------
	var built: Control = board._make_row()
	board._fill_row(built, 1, {"username": "someone", "contributed": 900,
		"lusions": 0, "deaths": 3, "lost": 400})
	var gold_cell: Label = built.get_node("gold")
	check("a row whose gold was mostly lost says so on the hover",
		gold_cell.tooltip_text.contains("400"), gold_cell.tooltip_text)

	board._fill_row(built, 1, {"username": "someone", "contributed": 900,
		"lusions": 0, "deaths": 0, "lost": 0})
	# REUSED ROWS ARE THE TRAP HERE, and this file has already been bitten by
	# it once with the name tint: an attribute that is only ever ADDED is an
	# attribute that never goes away, so the note would creep down the board as
	# ranks moved.
	check("and a reused row does not keep the last player's losses",
		not gold_cell.tooltip_text.contains("400"), gold_cell.tooltip_text)

	built.free()
	board.free()

	print("  the ranking is kept, and it admits what it is made of")


func _scripts_under(dir_path: String, found: Array[String] = []) -> Array[String]:
	"""Every .gd under a folder, recursively. Sorted, so a failure list is
	stable between runs rather than in whatever order the filesystem hands
	them over."""
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scripts_under(full, found)
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


func _labels_under(node: Node) -> PackedStringArray:
	"""Every Label text in `node`'s subtree, in tree order.

	SO A WRAPPER CAN BE PROVEN NOT TO HAVE EATEN ITS CONTENT. Wrapping a row in
	a box is two lines and it is entirely possible to build the box, return it,
	and never parent the row - which produces a tidy empty box that satisfies
	every check about the box itself. Reading the text back is the only question
	that notices."""
	var found := PackedStringArray()
	if node is Label:
		found.append((node as Label).text)
	for child in node.get_children():
		found.append_array(_labels_under(child))
	return found


func _within(index: int, limit: int) -> int:
	"""`index`, or -1 if it falls past `limit`. A limit of -1 means end of file.

	The companion to _first_code_index(): that one says "in code, not in a
	comment", this one says "and inside the function I meant". Needed three
	separate times in this suite, every time because the thing being searched
	for is common enough to appear in a later function - which reads as a pass.
	"""
	if index == -1:
		return -1
	if limit != -1 and index > limit:
		return -1
	return index


func _first_code_index(src: String, needle: String, from: int) -> int:
	"""Where `needle` first appears in CODE at or after `from`, ignoring comments.

	THIS EXISTS BECAUSE THE CHECK ABOVE FAILED ON CORRECT CODE. It looked for the
	first `gain_defense_xp(` after take_damage() and found it in the god-mode
	guard's own COMMENT - the paragraph explaining why the guard must come before
	that call names the call, three lines before the guard. So the check read
	"the XP happens before the guard" and went red on a file that is right.

	AND IT IS NOT A ONE-OFF. It is the fifth time in one day that a text check
	here has matched prose instead of code: a search for "already taken" hit the
	comment explaining why that phrase must never be used; a search for
	"backpack ledger" missed a page that says it, because markdown had wrapped
	the line; "const SKILL_IDS" matched inside "const SKILL_IDS_UNUSED".

	The pattern is structural rather than unlucky. This project deliberately
	explains its rules at length beside the code that implements them, so THE
	COMMENT EXPLAINING A RULE RELIABLY CONTAINS THE RULE'S OWN TEXT. Any text
	check written here is searching a haystack that is mostly made of needles.

	So: strip the comments, the way code_only() does in the API's
	test_ownership.py. Indices stay usable because each line is blanked in place
	rather than removed, which keeps every offset exactly where it was.
	"""
	return _code_only(src).find(needle, from)


func _code_only(src: String) -> String:
	"""The same text with every comment blanked and every offset preserved.

	SPLIT OUT of _first_code_index() when a second caller needed the stripped
	TEXT rather than one index into it - the audio scan reads whole call
	expressions out of it. One copy of the rule; two ways to ask."""
	var lines: PackedStringArray = src.split("\n")
	var rebuilt: PackedStringArray = PackedStringArray()
	for line in lines:
		var hash_at: int = line.find("#")
		if hash_at == -1:
			rebuilt.append(line)
		else:
			# Blank the comment, keep the length, so find() returns an index
			# into the ORIGINAL string.
			rebuilt.append(line.substr(0, hash_at).rpad(line.length(), " "))
	return "\n".join(rebuilt)


func _feed_holds_id(lines: Array, id: int) -> bool:
	for line in lines:
		if line is Dictionary and int(line.get("id", 0)) == id:
			return true
	return false


# =============================================================================
# A 401 HAS TO REACH SOMEBODY
# =============================================================================
# api.gd emits unauthorized_seen when an authenticated request comes back 401
# while this client holds a token. Its own comment says characterhud.gd answers
# it with an immediate heartbeat() - and for a long time nothing was connected,
# so that sentence described a wire nobody had run.
#
# The cost was measurable rather than theoretical. /api/staff/ban deletes the
# account's session rows in the same transaction that sets the ban, so the server
# revokes instantly; the client only noticed on the broadcast poll, which means a
# banned player went on playing for up to BROADCAST_POLL_SECONDS.
#
# WHY A 401 IS NOT ITSELF THE ANSWER, which is the part worth not losing:
# changing a password answers 401 for a mistyped CURRENT password. A client that
# treats every 401 as revocation signs people out for typos. So the signal is a
# prompt to ask, heartbeat_verdict() decides, and only "revoked" acts.
#
# Text checks, because the alternative is standing up a HUD, a live server and a
# real ban to watch one signal fire.

func _test_the_guild_tag_is_drawn_everywhere() -> void:
	section("GUILDS - a name twelve characters long, drawn on every surface")

	# =========================================================================
	# TWELVE, AND THE CLIENT AGREES WITH ITSELF ABOUT IT
	# =========================================================================
	# The cap dropped from 24 because the name is now drawn above a head, on
	# every chat line its members write, on the players menu and on the kingdom
	# board. At 24 characters that is a banner following somebody around.
	#
	# THE SERVER IS THE RULE AND THIS IS THE COURTESY. app.py's
	# GUILD_NAME_PATTERN is what actually refuses; the panel refuses early so a
	# hopeless name does not cost a round trip. What this suite can check is
	# that the client does not disagree with ITSELF - the regex, the number and
	# the sentence shown to the player all saying twelve.
	var panel: Script = require_script("res://src/ui/guild/guildpanel.gd",
		"the guild panel")
	if panel == null:
		print("  guild panel: not loadable, section skipped")
		return

	var panel_const: Dictionary = panel.get_script_constant_map()
	check("the panel caps a guild name at twelve",
		int(panel_const.get("MAX_NAME", 0)) == 12,
		panel_const.get("MAX_NAME"))
	check("and a username at twenty, which is a different limit",
		int(panel_const.get("MAX_USERNAME", 0)) == 20,
		panel_const.get("MAX_USERNAME"))

	# THE PATTERN IS MEASURED, NOT READ. Asserting the regex SPELLING would
	# pass on "{2,11}" written into a comment and fail on a harmless rewrite;
	# compiling it and asking what it accepts is the only version that tests
	# behaviour. Twelve characters in, thirteen out.
	var rule := RegEx.new()
	rule.compile(str(panel_const.get("NAME_PATTERN", "")))
	check("a twelve-character name is accepted",
		rule.search("Exactlytwelv") != null)
	check("a thirteen-character one is not",
		rule.search("Exactlythirte") == null)
	check("two characters is still too few", rule.search("No") == null)
	check("a bracket cannot get into a guild name",
		rule.search("A[color=red]") == null)

	var panel_src: String = FileAccess.get_file_as_string(
		"res://src/ui/guild/guildpanel.gd")
	# THE SENTENCE THE PLAYER READS MUST NOT NAME A DIFFERENT NUMBER. A refusal
	# that says "3 to 24" while the box stops at 12 is worse than no sentence.
	check("the refusal sentence is built from the constant, not typed again",
		_code_only(panel_src).contains("% MAX_NAME"),
		"a literal number here is a second copy of the rule")
	check("and no stale twenty-four is left in the panel's code",
		not _code_only(panel_src).contains("24"),
		"the cap moved; a 24 in code is the old one")

	# =========================================================================
	# ONE STATEMENT OF WHAT A TAG LOOKS LIKE
	# =========================================================================
	# The tag is drawn in four places. Four opinions about what a guild looks
	# like is how it stops being recognisable at a glance, which is the entire
	# point of having one.

	check("an empty guild draws nothing at all",
		Api.guild_tag_text("") == "" and Api.guild_tag_text("   ") == "",
		Api.guild_tag_text("  "))
	check("a guild is drawn in brackets",
		Api.guild_tag_text("ELUSION") == "[ELUSION]",
		Api.guild_tag_text("ELUSION"))
	check("and is stripped before it is wrapped",
		Api.guild_tag_text("  ELUSION  ") == "[ELUSION]",
		Api.guild_tag_text("  ELUSION  "))

	# THE CLIENT DOES NOT UPPERCASE, AND THAT IS THE POINT. guild_tag() in
	# app.py decides the letters and the bound; this only wraps what arrived.
	# A client that shaped the tag itself would be a client that could be
	# edited to draw something else.
	check("the client does not invent the letters",
		Api.guild_tag_text("Elusion") == "[Elusion]",
		"uppercasing here would be the client deciding what the server said")

	var api_const: Dictionary = Api.get_script().get_script_constant_map()
	var tag_colour = api_const.get("GUILD_TAG_COLOUR")
	check("the tag has one colour, owned by Api", tag_colour is Color, tag_colour)
	# NOT A RANK COLOUR. A guild is not a rank - the owner and a new player can
	# be in the same one - so a tag tinted like staff would say something about
	# its members that is not true.
	var ranks: Dictionary = api_const.get("RANK_COLOURS", {})
	var clashes: Array = []
	for rank_name in ranks:
		if ranks[rank_name] == tag_colour:
			clashes.append(rank_name)
	check("and it is none of the four rank colours", clashes.is_empty(), clashes)

	# =========================================================================
	# EVERY SURFACE READS IT OFF THE WIRE, AND FROM Api
	# =========================================================================
	var surfaces := {
		"res://src/ui/chat/chatpanel.gd": "a chat line",
		"res://src/ui/players/playerspanel.gd": "the players menu",
		"res://src/ui/kingdom/kingdomboard.gd": "the kingdom board",
		"res://src/characters/player.gd": "the nameplate",
	}
	for path in surfaces:
		var body: String = _code_only(FileAccess.get_file_as_string(path))
		check("%s asks Api for the tag" % surfaces[path],
			body.contains("Api.guild_tag_text("), path)
		check("%s takes Api's colour rather than its own" % surfaces[path],
			body.contains("GUILD_TAG_COLOUR") or path.ends_with("player.gd"),
			path)

	# =========================================================================
	# THE SEAM THE FILE ITSELF WARNS ABOUT
	# =========================================================================
	# _line_from_server() carries a long note saying the chat id was once
	# dropped HERE and every test passed, because every test built its own
	# dictionary by hand. A renderer cannot draw a field this function does not
	# copy, so the field is asserted in the function that makes the line rather
	# than in the one that paints it.
	var chat_src: String = FileAccess.get_file_as_string(
		"res://src/ui/chat/chatpanel.gd")
	var maker: int = _first_code_index(chat_src, "func _line_from_server(", 0)
	var maker_end: int = _first_code_index(chat_src, "\nfunc ", maker + 10)
	check("the line the poll makes carries the guild",
		_within(_first_code_index(chat_src, "\"guild_tag\"", maker), maker_end) != -1,
		"a field _line_from_server() does not copy cannot be drawn")

	# AND THE COLOUR, CHECKED BY RUNNING IT. The first live run of player-chosen
	# colours had every name in chat drawn in the default gold while the friends
	# list beside it showed the real colours - because name_hue was sent, and
	# this function did not copy it. The note on the function predicts exactly
	# that, and a text check for the key is the check that would have been
	# written instead: so this one hands it a real server message and reads the
	# drawn line.
	var chat_panel: Node = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	var made: Dictionary = chat_panel._line_from_server(
		{"id": 7, "by": "rowdy", "role": "player", "name_hue": 20.0, "body": "hi", "at": 1}, {})
	check("the line the poll makes carries the speaker's colour",
		made.get("name_hue") == 20.0, made)
	var never: Dictionary = chat_panel._line_from_server(
		{"id": 8, "by": "p", "role": "player", "name_hue": null, "body": "x", "at": 1}, {})
	check("and 'never chose' stays null rather than becoming a hue",
		never.has("name_hue") and never["name_hue"] == null, never)
	# append_text() leaves .text empty, so the line is read as the player sees
	# it (get_parsed_text) and its colour from the function that paints it.
	var drawn_line: RichTextLabel = chat_panel._node_for(made) as RichTextLabel
	check("and the line is drawn with the speaker's name",
		drawn_line != null and drawn_line.get_parsed_text().contains("rowdy: hi"),
		drawn_line.get_parsed_text() if drawn_line != null else "no label")
	var paint_at: int = _first_code_index(chat_src, "func _node_for(", 0)
	var paint_end: int = _first_code_index(chat_src, "\nfunc ", paint_at + 1)
	check("in the colour the line carries",
		_within(_first_code_index(chat_src, 'bbcode_name(_escape(who) + mark, line.get("name_hue"))',
			paint_at), paint_end) != -1)
	var staff_line: RichTextLabel = chat_panel._node_for(chat_panel._line_from_server(
		{"id": 9, "by": "helper", "role": "mod", "name_hue": 140, "body": "hi", "at": 1}, {})) as RichTextLabel
	check("a mod's line wears MOD before the name",
		staff_line != null and staff_line.get_parsed_text().contains("MOD")
		and staff_line.get_parsed_text().find("MOD") < staff_line.get_parsed_text().find("helper"),
		staff_line.get_parsed_text() if staff_line else "")
	if drawn_line != null:
		drawn_line.free()
	if staff_line != null:
		staff_line.free()
	chat_panel.free()

	# AND BOTH KINDS OF LINE DRAW IT. A picture posted by somebody in a guild
	# that did not say so would be the one message where the tag went missing.
	# _node_for(), NOT _line_label(). The first version of this check named a
	# function that does not exist in this file, _first_code_index() answered
	# -1, and the check failed by name - which is the good outcome and the
	# reason it is worth writing down: the sibling mistake in this suite's
	# history called board._build_row() instead of _make_row(), and GDScript
	# unwound the REST of that section while the run still reported 0 failed.
	var text_line: int = _first_code_index(chat_src, "func _node_for(", 0)
	var picture: int = _first_code_index(chat_src, "func _picture_node(", 0)
	check("a text line draws the tag",
		_within(_first_code_index(chat_src, "_guild_part(line)", text_line),
			_first_code_index(chat_src, "\nfunc ", text_line + 10)) != -1)
	check("and so does a picture",
		_within(_first_code_index(chat_src, "_guild_part(line)", picture),
			_first_code_index(chat_src, "\nfunc ", picture + 10)) != -1)

	# THE TAG IS ESCAPED LIKE EVERYTHING ELSE THAT REACHES THAT RENDERER. It
	# arrives wrapped in square brackets, which is the one character a public
	# chat log must never hand a BBCode parser: "[img]some-url[/img] makes the
	# client FETCH that url".
	var guild_part: int = _first_code_index(chat_src, "func _guild_part(", 0)
	check("and it is escaped before it is rendered",
		_within(_first_code_index(chat_src, "_escape(tag)", guild_part),
			_first_code_index(chat_src, "\nfunc ", guild_part + 10)) != -1,
		"an unescaped tag is a BBCode injection wearing a guild's name")

	# =========================================================================
	# THE NAMEPLATE IS TOLD, NOT LEFT TO ASK
	# =========================================================================
	# GET /api/guild is the only other route that says which guild you are in,
	# and NOTHING calls it on a timer. A tag fed from the guild panel would
	# appear whenever that panel happened to be opened and then go on being
	# whatever it was - including after you were kicked out. That is the shape
	# this project has spent the most time removing.
	var player_src: String = FileAccess.get_file_as_string(
		"res://src/characters/player.gd")
	check("set_nameplate takes a guild as well as a name and a rank",
		_code_only(player_src).contains(
			"func set_nameplate(display_name: String, rank: String, guild_tag: String"),
		"an argument, so a remote player can be told its own")

	# AND IT STILL WRITES THE LABEL, WHICH IS NOT AS OBVIOUS AS IT SOUNDS.
	# While the tag was being added, `_nameplate.text = text` was deleted by
	# accident and every check in this suite still passed - the plate is
	# verified by reading the file rather than by running it, so a blank
	# nameplate on every character in the game looked exactly like a green run.
	# Caught by diffing against the working copy; pinned here so it cannot
	# happen twice.
	var plate: int = _first_code_index(player_src, "func set_nameplate(", 0)
	var plate_end: int = _first_code_index(player_src, "\nfunc ", plate + 10)
	var writes: int = _first_code_index(player_src, "_nameplate.text = text", plate)
	check("and it actually writes the name onto the label",
		_within(writes, plate_end) != -1,
		"a plate that is positioned, coloured and never given any text")

	# AFTER the tag is folded in. Writing the label first would put the name on
	# screen and leave the guild in a local variable - which is the same defect
	# wearing a subtler hat, so it is checked by POSITION rather than presence.
	var folds: int = _first_code_index(player_src, "text = \"%s\\n%s\"", plate)
	check("after the guild has been folded into it, not before",
		_within(folds, plate_end) != -1 and folds < writes,
		"%d vs %d" % [folds, writes])

	var hud_src: String = FileAccess.get_file_as_string(
		"res://src/ui/characterhud.gd")
	var reader: int = _first_code_index(hud_src, "func _read_guild(", 0)
	var reader_end: int = _first_code_index(hud_src, "\nfunc ", reader + 10)
	check("the HUD reads the guild off the poll",
		_within(_first_code_index(hud_src, "data.get(\"guild_tag\"", reader),
			reader_end) != -1,
		"read from anywhere else and the plate is only as fresh as a panel")
	check("and puts it on the plate",
		_within(_first_code_index(hud_src, "set_nameplate(", reader), reader_end) != -1)

	# CALLED FROM THE POLL, not merely defined. A function nothing schedules is
	# a comment with a body on it - which is the defect this whole section is
	# about, so checking it by name is not optional.
	var poll_end: int = _first_code_index(hud_src, "func _read_pvp(", 0)
	check("_read_guild is called from the broadcast poll",
		_within(_first_code_index(hud_src, "_read_guild(data)", 0), poll_end) != -1,
		"defined but never called is the bug, not the fix")

	# =========================================================================
	# A DATE, FOR A THING THAT HAPPENED ON A DAY
	# =========================================================================
	check("a guild with no founding date shows nothing rather than a clock face",
		LocalTime.date(0) == "" and LocalTime.date(-1) == "",
		LocalTime.date(0))
	var founded: int = int(Time.get_unix_time_from_datetime_dict({
		"year": 2026, "month": 9, "day": 21, "hour": 12, "minute": 0, "second": 0}))
	var drawn: String = LocalTime.date(founded)
	check("and a real one reads as a date, not a timestamp",
		drawn.contains("2026") and not drawn.contains(":"), drawn)

	print("  guilds: twelve characters, one tag, four surfaces, drawn from the poll")



# =============================================================================
# PANELS BEHAVE LIKE WINDOWS
# =============================================================================
# Every panel drags by its header and resizes from any edge, through ONE
# component. The three checks that matter are the three defects in the drag
# statsscreen.gd used to carry on its own: a panel you can lose off the screen,
# a position that dies with the scene, and a per-frame poll.

const WINDOW_PANELS := [
	["res://src/ui/bank/bankinventory.gd", "res://scene/ui/bank/bankinventory.tscn", "bank"],
	["res://src/ui/chat/chatpanel.gd", "res://scene/ui/chat/chatpanel.tscn", "chat"],
	["res://src/ui/controls/controlspanel.gd", "res://scene/ui/controls/controlspanel.tscn", "controls"],
	["res://src/ui/cooking/cookingscreen.gd", "res://scene/ui/cooking/cookingscreen.tscn", "cooking"],
	["res://src/ui/equipment/equipmentpanel.gd", "res://scene/ui/equipment/equipmentpanel.tscn", "equipment"],
	["res://src/ui/friends/friendspanel.gd", "res://scene/ui/friends/friendspanel.tscn", "friends"],
	["res://src/ui/guild/guildpanel.gd", "res://scene/ui/guild/guildpanel.tscn", "guild"],
	["res://src/ui/inventory/inventoryscreen.gd", "res://scene/ui/inventory/inventory.tscn", "inventory"],
	["res://src/ui/kingdom/kingdomboard.gd", "res://scene/ui/kingdom/kingdomboard.tscn", "kingdom"],
	["res://src/ui/lootbag/lootbaginventory.gd", "res://scene/ui/lootbag/lootbaginventory.tscn", "lootbag"],
	["res://src/ui/menus/mapscreen.gd", "res://scene/ui/menus/mapscreen.tscn", "map"],
	["res://src/ui/menus/optionsscreen.gd", "res://scene/ui/menus/optionsscreen.tscn", "options"],
	["res://src/ui/owner/ownerpanel.gd", "res://scene/ui/owner/ownerpanel.tscn", "owner"],
	["res://src/ui/owner/itemspawner.gd", "res://scene/ui/owner/itemspawner.tscn", "itemspawner"],
	["res://src/ui/players/playerspanel.gd", "res://scene/ui/players/playerspanel.tscn", "players"],
	["res://src/ui/shop/shopinventory.gd", "res://scene/ui/shop/shopinventory.tscn", "shop"],
	["res://src/ui/staff/staffpanel.gd", "res://scene/ui/staff/staffpanel.tscn", "staff"],
	["res://src/ui/statsscreen.gd", "res://scene/ui/statsscreen.tscn", "charstats"],
	["res://src/ui/trade/tradepanel.gd", "res://scene/ui/trade/tradepanel.tscn", "trade"],
]


func _outer_margins(scene_text: String, header_parent: String) -> Dictionary:
	"""The four padding values of the MarginContainer a header sits inside.

	READ FROM THE SCENE TEXT rather than by loading it, for the same reason the
	header check beside it is: a scene naming art from the private pack will not
	load in a clone without the pack, and a check that fails on a clone and
	passes here is the worst kind.

	`header_parent` is the chain attach() found the header down — for example
	`mainpanel/margincontainer/vboxcontainer`. The SECOND segment is the outer
	MarginContainer, which is the one whose padding a grip sits in; the first is
	the frame and the third is the row box inside it.

	Returns {} when there is nothing to read, and the caller treats that as a
	failure rather than as permission."""
	var segments: PackedStringArray = header_parent.split("/")
	if segments.size() < 2:
		return {}

	var opener := '[node name="%s"' % segments[1]
	var parent := 'parent="%s"' % segments[0]
	var at: int = -1
	var scan: int = scene_text.find(opener)
	while scan != -1:
		var head_end: int = scene_text.find("]", scan)
		if head_end == -1:
			break
		if scene_text.substr(scan, head_end - scan).contains(parent):
			at = head_end
			break
		scan = scene_text.find(opener, scan + 1)
	if at == -1:
		return {}

	# BOUNDED TO THIS NODE'S OWN BLOCK. A margin constant belongs to whichever
	# [node] header it sits under, and reading past the next one would pick up a
	# child's padding and report it as the panel's — the same "bound the search
	# to the thing you meant" rule _within() exists for.
	var next_node: int = scene_text.find("[node ", at)
	var block: String = scene_text.substr(at, (next_node if next_node != -1
		else scene_text.length()) - at)

	var found := {}
	for side in ["left", "top", "right", "bottom"]:
		var key := "theme_override_constants/margin_%s = " % side
		var key_at: int = block.find(key)
		if key_at == -1:
			continue
		var from: int = key_at + key.length()
		var to: int = block.find("\n", from)
		if to == -1:
			to = block.length()
		found[side] = block.substr(from, to - from).strip_edges().to_int()
	return found


func _test_panels_are_windows() -> void:
	section("PANELS - drag by the header, resize from any edge, stay reachable")

	# =========================================================================
	# THE SCREEN EDGES ARE WALLS
	# =========================================================================
	# Checked first because it is the one defect with no way out from inside the
	# game. fit_to() is static and pure precisely so this can be asked in one
	# line instead of built in a viewport.
	#
	# THE RULE THIS REPLACED WAS DEFENSIBLE AND WRONG. It let a panel hang off an
	# edge and only guaranteed that a corner of the header stayed reachable -
	# which means a panel half off the bottom has its bottom edge past the glass,
	# so it cannot be resized from the bottom at all. That is what "i cant strech
	# down" is. So the rule now is the blunt one: a panel is ALWAYS ENTIRELY ON
	# SCREEN, and every edge is therefore always reachable.
	var screen := Vector2(1920, 1080)
	var panel := Vector2(400, 500)

	var far_right: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(9000, 100), panel), screen, PanelWindow.MIN_SIZE)
	check("a panel shoved off the right stops WITH ITS RIGHT EDGE AT THE WALL",
		is_equal_approx(far_right.position.x + far_right.size.x, screen.x),
		far_right)
	check("and it is not resized on the way",
		far_right.size.is_equal_approx(panel), far_right.size)

	var far_left: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(-9000, 100), panel), screen, PanelWindow.MIN_SIZE)
	check("shoved off the left, its left edge stops at zero",
		is_equal_approx(far_left.position.x, 0.0), far_left.position)

	var below: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(100, 9000), panel), screen, PanelWindow.MIN_SIZE)
	check("pushed off the bottom, THE BOTTOM EDGE IS STILL GRABBABLE",
		is_equal_approx(below.position.y + below.size.y, screen.y), below)

	var above: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(100, -500), panel), screen, PanelWindow.MIN_SIZE)
	check("and pushed off the top, the top edge is",
		is_equal_approx(above.position.y, 0.0), above.position)

	# A PANEL LARGER THAN THE SCREEN is the case a position-only clamp cannot
	# answer at all: there is nowhere to put it that is inside. It has to be
	# COMPRESSED, which is the whole reason fit_to settles the size first.
	var huge: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(-50, -50), Vector2(3000, 2000)), screen, PanelWindow.MIN_SIZE)
	check("a panel bigger than the screen is compressed, not moved off it",
		huge == Rect2(Vector2.ZERO, screen), huge)

	# THE SCREEN BEATS THE MINIMUM. Honouring a minimum size is worth less than
	# being able to reach the thing, and a panel wider than the window has an
	# edge nobody can get to.
	var tiny: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(0, 0), Vector2(400, 500)), Vector2(120, 90), PanelWindow.MIN_SIZE)
	check("on a screen smaller than the minimum, the screen wins",
		tiny.size.is_equal_approx(Vector2(120, 90)), tiny.size)

	# BUT THE MINIMUM WINS WHEN THERE IS ROOM FOR IT. A panel restored from a
	# config file written by hand, or by an older version, must not come back
	# crushed.
	var crushed: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(10, 10), Vector2(4, 4)), screen, PanelWindow.MIN_SIZE)
	check("a panel smaller than the minimum is grown back to it",
		crushed.size.is_equal_approx(PanelWindow.MIN_SIZE), crushed.size)

	# GROWN IN THE CORNER IS THE CASE THAT PINS THE ORDER OF THE TWO HALVES,
	# and it was missing until a sabotage run went green without it. Settling
	# the position before the size looks identical on every check above - an
	# oversized panel compresses either way - and differs only here, where the
	# size is about to GROW and a position bounded by the old small size is
	# looser than the grown panel needs. Sabotage: swap the two blocks in
	# fit_to() and this is the only line that goes red.
	var grown: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(1900, 1060), Vector2(4, 4)), screen, PanelWindow.MIN_SIZE)
	check("a crushed panel in the corner is grown AND pulled back on screen",
		is_equal_approx(grown.position.x + grown.size.x, screen.x)
			and is_equal_approx(grown.position.y + grown.size.y, screen.y),
		grown)

	# ALREADY ON SCREEN MEANS UNTOUCHED. A fit that nudges a panel nobody
	# dragged is a panel that drifts.
	var settled: Rect2 = PanelWindow.fit_to(
		Rect2(Vector2(300, 200), panel), screen, PanelWindow.MIN_SIZE)
	check("a panel already on screen is not moved or resized",
		settled == Rect2(Vector2(300, 200), panel), settled)

	check("the smallest panel is positive in both axes",
		PanelWindow.MIN_SIZE.x > 0.0 and PanelWindow.MIN_SIZE.y > 0.0)

	# =========================================================================
	# AND THE WALL STOPS A RESIZE RATHER THAN BOUNCING IT
	# =========================================================================
	# THE BUG THIS EXISTS FOR IS THE ONE THAT LOOKS LIKE IT IS ALREADY FIXED.
	# resize_rect() could have left the wall to fit_to() and every check above
	# would still pass - but fit_to() is a rule about a FINISHED rectangle. Drag
	# the bottom edge 3000px below the floor of the screen and it settles the
	# size first: the panel is too tall, so it is shortened, and the shortened
	# panel then has to go somewhere inside the screen, which is the TOP. The
	# panel leaves the cursor and jumps to the other end of the glass.
	#
	# So every one of these asserts the OPPOSITE EDGE HAS NOT MOVED. That is the
	# difference between a wall and a bounce, and it is the only thing that tells
	# the two implementations apart.
	var start := Rect2(Vector2(700, 600), Vector2(400, 300))
	var floor2: Vector2 = PanelWindow.MIN_SIZE

	var pushed_down: Rect2 = PanelWindow.resize_rect(
		start, Vector2(0, 3000), PanelWindow.EDGE_BOTTOM, floor2, screen)
	check("the bottom edge stops at the floor of the screen",
		is_equal_approx(pushed_down.position.y + pushed_down.size.y, screen.y),
		pushed_down)
	check("AND THE TOP EDGE DOES NOT MOVE - the panel does not jump",
		is_equal_approx(pushed_down.position.y, 600.0), pushed_down.position)

	var pushed_right: Rect2 = PanelWindow.resize_rect(
		start, Vector2(3000, 0), PanelWindow.EDGE_RIGHT, floor2, screen)
	check("the right edge stops at the right wall",
		is_equal_approx(pushed_right.position.x + pushed_right.size.x, screen.x),
		pushed_right)
	check("and the left edge does not move",
		is_equal_approx(pushed_right.position.x, 700.0), pushed_right.position)

	var pushed_up: Rect2 = PanelWindow.resize_rect(
		start, Vector2(0, -3000), PanelWindow.EDGE_TOP, floor2, screen)
	check("the top edge stops at zero",
		is_equal_approx(pushed_up.position.y, 0.0), pushed_up)
	check("and the bottom edge does not move",
		is_equal_approx(pushed_up.position.y + pushed_up.size.y, 900.0), pushed_up)

	var pushed_left: Rect2 = PanelWindow.resize_rect(
		start, Vector2(-3000, 0), PanelWindow.EDGE_LEFT, floor2, screen)
	check("the left edge stops at zero",
		is_equal_approx(pushed_left.position.x, 0.0), pushed_left)
	check("and the right edge does not move",
		is_equal_approx(pushed_left.position.x + pushed_left.size.x, 1100.0),
		pushed_left)

	# A CORNER INTO A CORNER is the case he described - "like forcing something
	# in a corner is like a wall" - and it is worth its own check because it is
	# the one where both axes clamp at once.
	var cornered: Rect2 = PanelWindow.resize_rect(
		start, Vector2(3000, 3000),
		PanelWindow.EDGE_RIGHT | PanelWindow.EDGE_BOTTOM, floor2, screen)
	check("driven into the bottom-right corner it fills the room left and stops",
		cornered == Rect2(Vector2(700, 600), Vector2(screen.x - 700.0, screen.y - 600.0)),
		cornered)

	# A DRAG THAT NEVER REACHES A WALL MUST BE UNTOUCHED BY IT. Without this,
	# "clamp everything to the screen" passes every check above while quietly
	# rounding every ordinary resize.
	var ordinary: Rect2 = PanelWindow.resize_rect(
		start, Vector2(60, 40),
		PanelWindow.EDGE_RIGHT | PanelWindow.EDGE_BOTTOM, floor2, screen)
	check("an ordinary resize is exactly the mouse movement",
		ordinary == Rect2(Vector2(700, 600), Vector2(460, 340)), ordinary)

	# AN EDGE NOT BEING DRAGGED IS NOT TOUCHED AT ALL.
	check("dragging one edge moves one edge",
		is_equal_approx(ordinary.position.x, 700.0)
			and is_equal_approx(ordinary.position.y, 600.0))

	# =========================================================================
	# EIGHT GRIPS, BUILT ON A REAL CONTROL
	# =========================================================================
	# Behavioural rather than textual: attach() is asked to dress a bare Control
	# and the result is inspected. It works outside the tree because every call
	# that needs a viewport is guarded - which is worth having anyway, since a
	# panel is attached in _ready() and may be built before it is added.
	var host := Control.new()
	# AUTHORED CENTRED, exactly as every real panel is. The first version of
	# this built a bare Control - whose anchors are already zero - so the
	# "taken off its centre anchor" check below passed whether or not the code
	# under test ran at all. Sabotage caught it: deleting _take_control() left
	# the suite green. A check whose subject already satisfies it is not a
	# check.
	host.anchor_left = 0.5
	host.anchor_top = 0.5
	host.anchor_right = 0.5
	host.anchor_bottom = 0.5
	host.offset_left = -200.0
	host.offset_top = -150.0
	host.offset_right = 200.0
	host.offset_bottom = 150.0
	var grip_bar := Control.new()
	host.add_child(grip_bar)
	# KEY "" MEANS DO NOT PERSIST. A suite that writes user://panels.cfg would
	# scribble over the player's real layout on every run.
	var dressed: PanelWindow = PanelWindow.attach(host, "", grip_bar)

	check("a panel with an explicit header attaches", dressed != null)
	if dressed == null:
		host.queue_free()
		print("  panels: attach refused, section cut short")
		return

	var names := ["gripleft", "gripright", "griptop", "gripbottom",
		"griptopleft", "griptopright", "gripbottomleft", "gripbottomright"]
	var found := 0
	for grip_name in names:
		if host.has_node(NodePath(grip_name)):
			found += 1
	check("all eight grips exist", found == 8, "%d of 8" % found)

	# THE CORNERS ARE ADDED LAST so they receive input in front of the edges
	# they overlap. Without that, a drag from the very corner resizes one axis
	# and the player quietly cannot make a panel smaller in both directions.
	var edge_at: int = host.get_node("gripright").get_index()
	var corner_at: int = host.get_node("gripbottomright").get_index()
	check("corners sit in front of edges", corner_at > edge_at,
		"corner %d vs edge %d" % [corner_at, edge_at])

	check("every grip stops the mouse rather than ignoring it",
		host.get_node("gripleft").mouse_filter == Control.MOUSE_FILTER_STOP)
	check("and says so with the cursor",
		host.get_node("gripleft").mouse_default_cursor_shape == Control.CURSOR_HSIZE
		and host.get_node("griptop").mouse_default_cursor_shape == Control.CURSOR_VSIZE
		and host.get_node("gripbottomright").mouse_default_cursor_shape == Control.CURSOR_FDIAGSIZE
		and host.get_node("griptopright").mouse_default_cursor_shape == Control.CURSOR_BDIAGSIZE)
	check("the header is the move handle",
		grip_bar.mouse_default_cursor_shape == Control.CURSOR_MOVE)

	check("the panel is taken off its centre anchor",
		host.anchor_left == 0.0 and host.anchor_top == 0.0
		and host.anchor_right == 0.0 and host.anchor_bottom == 0.0,
		"%s %s %s %s" % [host.anchor_left, host.anchor_top, host.anchor_right, host.anchor_bottom])

	# =========================================================================
	# RESIZING HAS A FLOOR, AND THE LEFT EDGE IS THE HARD ONE
	# =========================================================================
	host.position = Vector2(500, 400)
	host.size = Vector2(400, 300)
	dressed._resizing = PanelWindow.EDGE_RIGHT | PanelWindow.EDGE_BOTTOM
	dressed._resize_from = Rect2(host.position, host.size)
	dressed._resize_mouse = Vector2(900, 700)
	dressed._resize_to(Vector2(1100, 800))
	check("dragging a corner outward grows the panel",
		host.size == Vector2(600, 400), host.size)
	check("and does not move it", host.position == Vector2(500, 400), host.position)

	# Crushed from the bottom-right: the size stops at the floor.
	dressed._resize_to(Vector2(0, 0))
	var floor_size: Vector2 = Vector2(
		maxf(host.custom_minimum_size.x, PanelWindow.MIN_SIZE.x),
		maxf(host.custom_minimum_size.y, PanelWindow.MIN_SIZE.y))
	check("it cannot be crushed below the minimum",
		host.size.x >= floor_size.x and host.size.y >= floor_size.y,
		"%s vs floor %s" % [host.size, floor_size])

	# DRAGGING A LEFT EDGE MOVES THE PANEL AS WELL AS SIZING IT, so the floor
	# has to stop the LEFT EDGE rather than the width. Bounding the width
	# instead lets the panel keep sliding right after it has hit its minimum,
	# which reads as the panel running away from the cursor.
	host.position = Vector2(500, 400)
	host.size = Vector2(400, 300)
	dressed._resizing = PanelWindow.EDGE_LEFT
	dressed._resize_from = Rect2(host.position, host.size)
	dressed._resize_mouse = Vector2(500, 500)
	dressed._resize_to(Vector2(5000, 500))
	var right_edge: float = host.position.x + host.size.x
	check("dragging the left edge past the right one stops at the minimum",
		host.size.x >= floor_size.x, host.size)
	check("and the right edge has not moved", is_equal_approx(right_edge, 900.0),
		right_edge)

	host.queue_free()

	# =========================================================================
	# FLATTENING THE ANCHORS MUST NOT MOVE THE PANEL
	# =========================================================================
	# THIS ONE NEEDS A REAL PARENT, IN THE TREE, and that is the whole reason it
	# is a block of its own. An orphan Control has no parent rectangle, so an
	# anchor of 0.5 and an anchor of 0 resolve to the same place and the claim
	# cannot be wrong. Sabotage proved it: passing `true` to set_anchors_preset
	# - the one real mistake available in that call - left the suite green.
	#
	# Measured on 4.6.1, a 400x300 control centred in an 800x600 parent:
	#     keep_offsets=false  rect stays (200, 150)
	#     keep_offsets=true   rect jumps to (-200, -150)
	# and it settles synchronously, so no frame has to be awaited here.
	var stage := Control.new()
	stage.size = Vector2(800, 600)
	add_child(stage)
	var centred := Control.new()
	stage.add_child(centred)
	centred.anchor_left = 0.5
	centred.anchor_top = 0.5
	centred.anchor_right = 0.5
	centred.anchor_bottom = 0.5
	centred.offset_left = -200.0
	centred.offset_top = -150.0
	centred.offset_right = 200.0
	centred.offset_bottom = 150.0
	var authored := Rect2(centred.position, centred.size)
	var bar := Control.new()
	centred.add_child(bar)
	var flattened: PanelWindow = PanelWindow.attach(centred, "", bar)

	check("a centred panel is flattened to the top left",
		flattened != null and centred.anchor_left == 0.0 and centred.anchor_top == 0.0
		and centred.anchor_right == 0.0 and centred.anchor_bottom == 0.0)
	check("and it does not move while that happens",
		centred.position.is_equal_approx(authored.position)
		and centred.size.is_equal_approx(authored.size),
		"%s -> %s" % [authored, Rect2(centred.position, centred.size)])

	stage.queue_free()

	# =========================================================================
	# EVERY PANEL IS WIRED, AND EVERY HEADER IS WHERE THE COMPONENT LOOKS
	# =========================================================================
	var keys_seen := {}
	for entry in WINDOW_PANELS:
		var script_path: String = entry[0]
		var scene_path: String = entry[1]
		var layout_key: String = entry[2]
		var short: String = script_path.get_file()

		var body: String = _code_only(FileAccess.get_file_as_string(script_path))
		check("%s attaches a window" % short,
			body.contains('PanelWindow.attach(self, "%s")' % layout_key),
			script_path)

		# THE KEY IS READ OUT OF THE FILE, not taken from the table above. The
		# first version checked WINDOW_PANELS against itself for duplicates -
		# and that table is written by hand with unique keys, so the check was
		# a tautology that could never fail however the panels were wired.
		# Sabotage caught it: giving two panels the same key left it green.
		var declared := ""
		var opener := 'PanelWindow.attach(self, "'
		var at: int = body.find(opener)
		if at != -1:
			var from: int = at + opener.length()
			var to: int = body.find('"', from)
			if to != -1:
				declared = body.substr(from, to - from)

		# A DUPLICATE KEY MAKES TWO PANELS SHARE ONE SAVED RECTANGLE, so
		# opening the second moves the first. Invisible until somebody notices
		# a panel jumping.
		check("%s has a key of its own" % short,
			declared != "" and not keys_seen.has(declared),
			"'%s' (already seen: %s)" % [declared, keys_seen.keys()])
		keys_seen[declared] = true

		# THE HEADER IS WHERE attach() LOOKS FOR IT. Read out of the scene TEXT
		# rather than by loading it: a scene that names art from the private
		# pack will not load in a clone without it, and a check that fails on a
		# clone and passes here is the worst kind.
		var scene_text: String = FileAccess.get_file_as_string(scene_path)
		var marker: int = scene_text.find('[node name="headerpanel"')
		var chain := ""
		if marker != -1:
			var line_end: int = scene_text.find("]", marker)
			var line: String = scene_text.substr(marker, line_end - marker)
			var parent_at: int = line.find('parent="')
			if parent_at != -1:
				var from: int = parent_at + 8
				var to: int = line.find('"', from)
				chain = line.substr(from, to - from)
		check("%s keeps its header where the component looks" % scene_path.get_file(),
			PanelWindow.HEADER_PATHS.has(chain + "/headerpanel"),
			"found '%s'; known: %s" % [chain, ", ".join(PanelWindow.HEADER_PATHS)])

		# A GRIP THICKER THAN THE PADDING IT LIVES IN IS A GRIP THAT STEALS
		# CLICKS, and it steals them invisibly, because a grip draws nothing.
		# CORNER was 12 and the overhang landed on the HEADER - the one thing a
		# panel must be grabbable by - which reached him as "i cannot grab the
		# header". Then 8, which was still two pixels too many on chat and
		# equipment. This reads the padding out of each scene rather than
		# trusting the number written next to the constant, because that number
		# was wrong twice and looked right both times.
		var pad: Dictionary = _outer_margins(scene_text, chain)
		# NO PADDING AT ALL IS A FAILURE, not a pass. A MarginContainer with no
		# overrides pads by whatever the theme says, which is nothing, and then
		# EVERY grip is on top of the content. Letting an empty reading through
		# would make this check disappear the moment it was needed most.
		var thinnest: float = 1.0e9
		for side in pad:
			thinnest = minf(thinnest, float(pad[side]))
		check("%s: no grip reaches past its padding onto the content" % short,
			not pad.is_empty() and PanelWindow.GRIP <= thinnest
				and PanelWindow.CORNER <= thinnest,
			"padding %s, thinnest %s; grip %s, corner %s"
				% [pad, thinnest, PanelWindow.GRIP, PanelWindow.CORNER])

	check("nineteen panels are windows - the owner's item menu is the nineteenth", keys_seen.size() == 19, keys_seen.size())

	# AND THE TABLE ABOVE IS COMPLETE. It is typed by hand, and the GM panel
	# became a window without being added to it - every check in this loop then
	# skipped it, green, while PANEL GEOMETRY (which finds panels by reading the
	# scripts) had already counted seventeen. The table is checked against that
	# same discovery now, so a panel cannot become a window without these checks
	# knowing.
	var discovered: Array[String] = []
	_find_window_scenes("res://scene/ui", discovered)
	var tabled: Dictionary = {}
	for entry in WINDOW_PANELS:
		tabled[entry[1]] = true
	var untabled: Array[String] = []
	for scene_path in discovered:
		if not tabled.has(scene_path):
			untabled.append(scene_path)
	check("every scene whose script attaches a window is in WINDOW_PANELS",
		untabled.is_empty() and discovered.size() >= 14,
		"missing: %s (%d discovered)" % [untabled, discovered.size()])

	# THE PADDING READER, ASKED DIRECTLY, because one thing it does cannot be
	# proven by any scene in the project. _outer_margins() stops at the next
	# [node] header so a CHILD's padding is never reported as the panel's - and
	# removing that bound changes nothing on all sixteen, because every outer
	# container happens to declare its own margins first. Sabotage went green.
	#
	# A guard that no real input exercises is the thing this file keeps finding
	# in its own checks, so it gets an input made for it instead of a comment
	# promising it works. The fabricated scene below is a panel whose
	# MarginContainer declares NOTHING and whose child declares 3 - the exact
	# shape that would otherwise report a 3-pixel ceiling for a panel that has
	# no padding at all, and quietly fail the wrong panels for the wrong reason.
	var fake := """[node name="mainpanel" type="PanelContainer"]
[node name="margin" type="MarginContainer" parent="mainpanel"]
[node name="rows" type="VBoxContainer" parent="mainpanel/margin"]
theme_override_constants/margin_left = 3
theme_override_constants/margin_top = 3
[node name="headerpanel" type="PanelContainer" parent="mainpanel/margin/rows"]
"""
	check("the padding reader stops at its own node and does not read a child's",
		_outer_margins(fake, "mainpanel/margin/rows").is_empty(),
		_outer_margins(fake, "mainpanel/margin/rows"))

	# And it does read the real thing when the real thing is there, so the
	# check above cannot be satisfied by a reader that always returns nothing.
	var fake_padded := """[node name="mainpanel" type="PanelContainer"]
[node name="margin" type="MarginContainer" parent="mainpanel"]
theme_override_constants/margin_left = 9
theme_override_constants/margin_top = 7
[node name="rows" type="VBoxContainer" parent="mainpanel/margin"]
theme_override_constants/margin_left = 3
"""
	check("and it reads the node it was actually asked about",
		_outer_margins(fake_padded, "mainpanel/margin/rows") == {"left": 9, "top": 7},
		_outer_margins(fake_padded, "mainpanel/margin/rows"))

	# =========================================================================
	# AND THERE IS ONLY ONE IMPLEMENTATION
	# =========================================================================
	# statsscreen.gd carried its own drag. Leaving it in place beside the
	# component would mean two things moving one panel, which is worse than
	# either - and it is the copy that would have been pasted into the other
	# fifteen.
	var stats: String = _code_only(FileAccess.get_file_as_string(
		"res://src/ui/statsscreen.gd"))
	check("the old hand-rolled drag is gone, not left beside the new one",
		not stats.contains("_is_dragging") and not stats.contains("_on_header_gui_input"),
		"two implementations moving one panel")
	check("and its per-frame mouse poll went with it",
		not stats.contains("func _process("),
		"_process polled the cursor every frame whether or not anything was moving")

	# NOBODY ELSE POLLS EITHER. The component reads motion events; a panel that
	# grew its own _process to chase the cursor would be the same defect
	# returning by a different door.
	var pollers: Array[String] = []
	for entry in WINDOW_PANELS:
		var body: String = _code_only(FileAccess.get_file_as_string(entry[0]))
		if body.contains("get_global_mouse_position()"):
			pollers.append(entry[0].get_file())
	check("no panel chases the cursor itself", pollers.is_empty(), pollers)

	print("  panels: %d windows, 8 grips each, one component" % keys_seen.size())


func _test_the_client_says_which_build_it_is() -> void:
	section("THE BUILD GATE - every request stamps its build, all three doors")

	var api: String = FileAccess.get_file_as_string("res://src/systems/api.gd")
	check("api.gd is readable", api.length() > 0)

	var api_script: Script = load("res://src/systems/api.gd") as Script
	check("api.gd compiles", api_script != null)
	if api_script == null:
		print("  build gate: api.gd would not load, section cut short")
		return

	var consts: Dictionary = api_script.get_script_constant_map()

	# THE NUMBER THE SERVER COMPARES. An integer on purpose - the only question
	# the gate asks is "older than", and integers answer that without a parser.
	check("the client declares a build number",
		consts.has("BUILD") and typeof(consts["BUILD"]) == TYPE_INT,
		"a version string would need a parser on both sides")
	check("and it is a real build, not zero",
		int(consts.get("BUILD", 0)) > 0,
		"0 is the server's word for a client from before any of this existed")
	check("there is a display version for humans, separate from it",
		consts.has("DISPLAY_VERSION"),
		"renumbering what people read must not move what the server compares")

	# THE HEADER NAME IS A CONTRACT WITH app.py. Rename one side only and the
	# gate does not error - it silently reads every client as ancient, and
	# since the gate ships disarmed, nothing refuses anybody and nothing says
	# so. A mismatch that fails closed would announce itself; this one does not.
	check("the header name matches the one app.py reads",
		str(consts.get("BUILD_HEADER", "")) == "X-Elusion-Build",
		str(consts.get("BUILD_HEADER", "")))

	# ALL THREE HEADER BUILDERS, and this is the check with the most to catch.
	# api.gd builds headers in three separate functions - the raw-body poster,
	# the GET helper and the main _request - and the gate is only as good as the
	# least of them. A route reached through a builder that forgot the stamp
	# reads as a pre-versioning client for ever, which is invisible precisely
	# because the default is to refuse nobody.
	# COUNTED AS `headers := PackedStringArray`, NOT AS `PackedStringArray`.
	# The loose version went red on its first run claiming a missing stamp, and
	# the fourth "builder" was
	#
	#     var order: PackedStringArray = ["player", "mod", "dev", "owner"]
	#
	# which is the rank ladder and has nothing to do with headers. A false alarm
	# is how a check gets switched off - this file says so twice already - and
	# it would have been a particularly bad one, because the honest reading of
	# "4 builders, 3 stamped" is that a real hole exists.
	var code: String = _code_only(api)
	var builders: int = code.count("headers := PackedStringArray")
	var stamps: int = code.count("BUILD_HEADER + \": \"")
	check("every header builder stamps the build",
		builders >= 3 and stamps >= builders,
		"%d builders, %d stamped - a builder without the stamp is a silent hole"
			% [builders, stamps])

	# LEARNED FROM THE REFUSAL, not only from a poll. By the time a 426 arrives
	# the client is already being turned away from everything except
	# /api/status, so the refusal body is the fastest place to find out.
	# THE COLON IS LOAD-BEARING. Written as contains("status == 426") this went
	# GREEN on a sabotage that changed the code to `status == 4260` - which
	# recognises nothing, and which the substring matches perfectly. The same
	# family as `const SKILL_IDS` matching inside `const SKILL_IDS_UNUSED`, and
	# it is worth the four extra characters every time.
	check("a 426 is recognised", code.contains("status == 426:"),
		"otherwise it falls through as a generic error and says nothing useful")
	check("and it is turned into words the login screen already shows",
		_within(_first_code_index(code, "signout_notice",
			code.find("status == 426:")), -1) != -1,
		"signout_notice is the path a ban already uses to explain itself")

	# /api/status IS THE ONE ROUTE THE GATE NEVER REFUSES, which is what makes
	# it reachable exactly when it is needed. Asking it BEFORE the session probe
	# matters: a refused client that asked the other way round would read
	# "could not resume your session" about a version mismatch.
	var probe_at: int = code.find("func probe_and_resume(")
	var probe_end: int = code.find("\nfunc ", probe_at + 8)
	var refresh_at: int = _within(
		_first_code_index(code, "refresh_build_info()", probe_at), probe_end)
	var session_at: int = _within(
		_first_code_index(code, "\"/api/auth/session\"", probe_at), probe_end)
	check("the login probe asks about builds",
		refresh_at != -1, "nothing would ever read /api/status on an ordinary client")
	check("and asks BEFORE the session probe it might be refused on",
		refresh_at != -1 and session_at != -1 and refresh_at < session_at,
		"refresh %d, session %d" % [refresh_at, session_at])

	# NOT ASKED IS NOT THE SAME AS NOT GATED. -1 rather than 0, because 0 is a
	# real answer from the server meaning the gate is off - and a client that
	# read a timeout as "off" would cheerfully report itself current, which is
	# the exact failure this feature exists to remove.
	check("unasked is -1, not 0",
		int(api_script.get("server_min_build")) == -1
			and int(api_script.get("server_current_build")) == -1,
		"%s / %s" % [api_script.get("server_min_build"),
			api_script.get("server_current_build")])

	# THE TWO QUESTIONS ARE SEPARATE ON PURPOSE. "There is something newer" is
	# not "you will be refused", and collapsing them would make the soft notice
	# impossible - which is the whole value of shipping the gate disarmed.
	check("behind and refused are different questions",
		code.contains("func build_is_outdated(") and code.contains("func build_is_refused("),
		"one function for both cannot say 'an update exists' without crying wolf")
	check("being behind reads the CURRENT build",
		_first_code_index(code, "server_current_build > BUILD",
			code.find("func build_is_outdated(")) != -1)
	check("being refused reads the MINIMUM",
		_first_code_index(code, "BUILD < server_min_build",
			code.find("func build_is_refused(")) != -1)

	print("  the client names itself; the server may refuse it, and does not by default")


func _test_unauthorized_is_answered() -> void:
	section("A 401 REACHES SOMEBODY — the revocation shortcut is wired")

	var api_src: String = FileAccess.get_file_as_string("res://src/systems/api.gd")
	var hud_src: String = FileAccess.get_file_as_string("res://src/ui/characterhud.gd")

	check("api.gd still emits unauthorized_seen", api_src.contains("unauthorized_seen.emit()"))
	check("and something connects it",
		hud_src.contains("Api.unauthorized_seen.connect("),
		"emitted and unheard means a ban lands up to BROADCAST_POLL_SECONDS late")
	check("the handler asks heartbeat() rather than deciding for itself",
		hud_src.contains("await Api.heartbeat()"),
		"a 401 is not proof - a mistyped current password answers 401 too")
	check("and only a revoked verdict signs anyone out",
		hud_src.contains("if verdict == \"revoked\":"),
		"acting on anything else turns a server hiccup into a mass kick")
	check("the probe cannot storm",
		hud_src.contains("_revocation_probe_in_flight"),
		"several panels can each 401 in the same moment; one probe answers all")
	check("and api.gd still excludes the probe's own path from the signal",
		api_src.contains("path != \"/api/auth/session\""),
		"without it the probe's own 401 calls the handler back forever")

	print("  server revokes in one transaction; the client now asks at once")


# =============================================================================
# THE LOGIN SCREEN'S FOUR ANSWERS LOOK LIKE FOUR ANSWERS
# =============================================================================
# %errorlabel carries every word this screen says about an account, and its colour
# was a theme_override in loginmenu.tscn - one red, for everything. So the two
# messages that mean it is WORKING ("Connecting...", "Loading characters...")
# arrived in the same red as "Incorrect password", while the recovery form, the
# email prompt and the connection banner on the SAME SCREEN each already took a
# colour per state. The main line was the one that could not change.
#
# Four states because app.py gives four kinds of answer, not because four is tidy:
# /login answers 200/400/401/403/429 and /register answers 201/400/403/409/429.
# The split that earns its keep is the last two - "what you typed is wrong" asks
# the player to try again and a ban does not, and a ban in the typo colour asks
# somebody to retype a password that was never the problem.
#
# THE 409 HAS ONE HOME: the "Create account" form, where it means exactly what
# it says - the name is taken. Signing in used to fall back to registering the
# name, and there a 409 meant a wrong password; that fallback is gone (see
# _test_signing_in_never_makes_an_account), and so is the need to translate it.
#
# Text checks. The alternative is driving a real form against a live server
# through four different refusals, and a colour has no symptom a headless run can
# assert - which is exactly why one red went unnoticed across every state.
func _test_login_states_are_distinct() -> void:
	section("LOGIN SCREEN — working, welcome, refused and blocked each look different")

	var src: String = FileAccess.get_file_as_string("res://src/ui/menus/loginmenu.gd")
	check("loginmenu.gd is readable", src.length() > 0)

	# One writer. A direct .text assignment is how a fifth state gets added in
	# whatever colour the fourth one happened to leave behind.
	check("every line goes through _say()", src.contains("func _say(message: String, color: Color)"))
	check("and nothing writes the label directly",
		not src.contains("errorlabel.text ="),
		"a direct write inherits the previous state's colour")

	# FOUR NAMES, FOUR DIFFERENT COLOURS - and this half is not a text check.
	# get_script_constant_map() hands back the real Color values, so "distinct" is
	# measured rather than inferred from four different spellings. Two names
	# pointing at one colour is precisely the bug being fixed, in a new disguise.
	var login_script: Script = load("res://src/ui/menus/loginmenu.gd") as Script
	check("loginmenu.gd's constants are readable", login_script != null)
	if login_script != null:
		var consts: Dictionary = login_script.get_script_constant_map()
		var seen: Array[Color] = []
		for const_name in ["SAY_WORKING", "SAY_GOOD", "SAY_REFUSED", "SAY_BLOCKED"]:
			check("%s is defined" % const_name, consts.has(const_name))
			if consts.has(const_name) and consts[const_name] is Color:
				seen.append(consts[const_name])
		check("and the four are four different colours", _all_colours_differ(seen),
			"two states sharing a colour is the bug this check exists for: %s" % str(seen))

	check("and all four are used at a call site",
		src.contains("SAY_WORKING)") and src.contains("SAY_GOOD)")
			and src.contains("SAY_REFUSED)") and src.contains("_refusal_colour("),
		"a colour that is declared and never passed is a colour nobody sees")

	# The success state exists at all. It did not before: the screen went straight
	# from "Loading characters..." to a scene change, so a successful login and a
	# stalled one looked the same for as long as the load took.
	check("a successful login says so, in the good colour",
		src.contains("_say(\"Welcome, %s\" % who, SAY_GOOD)"),
		"success was silent - the same grey progress line either way")
	check("and it greets the server's spelling of the name, not the typed one",
		src.contains("if Api.username != \"\":"),
		"username is UNIQUE COLLATE NOCASE; the stored case is the real one")

	# THE 409 BELONGS TO THE SIGN-UP FORM. Signing in used to fall back to
	# registering the name, so a 409 there meant "the account exists, the
	# password was wrong" and the screen had to say "Incorrect password" for it.
	# Sign-in never registers now (_test_signing_in_never_makes_an_account), so
	# the only 409 this screen sees is from "Create account" - where "taken" is
	# simply true - and "taken" must not be said anywhere else.
	var create_body: String = _func_body(src, "func _create_account(")
	check("a 409 on the sign-up form says the name is taken",
		create_body.contains("if created.status == 409:")
			and create_body.contains("_say(\"That name is taken."),
		"a sign-up form that will not say a name is taken is not a sign-up form")
	var says_taken: String = ""
	for line in src.split("\n"):
		var lower: String = line.to_lower()
		if lower.contains("_say(") and lower.contains("taken") and not create_body.contains(line):
			says_taken = line.strip_edges()
			break
	check("and nothing else on the screen says a name is taken", says_taken == "",
		"only the sign-up form has a name to be taken: %s" % says_taken)

	# A ban is not a typo.
	check("403, 429 and 503 are not dressed as typos",
		src.contains("if status == 403 or status == 429 or status == 503:"),
		"none of the three get better by retyping anything")
	check("and a server-side signout lands in the blocked colour",
		src.contains("_say(Api.signout_notice, SAY_BLOCKED)"),
		"a kick read as a failed login is the one player who must not misread it")

	print("  four server answers, four colours; a 409 is the sign-up form's")


func _all_colours_differ(colours: Array[Color]) -> bool:
	if colours.size() < 4:
		return false
	for i in range(colours.size()):
		for j in range(i + 1, colours.size()):
			if colours[i].is_equal_approx(colours[j]):
				return false
	return true


# =============================================================================
# THE HELPER SCRIPTS STAY PURE ASCII
# =============================================================================
# run_tests.ps1 is the documented way to run this suite, and split_art.ps1 is
# the documented way to separate the licensed art pack from original work. Both
# are among the first things a person who clones this repository runs.
#
# WHY ASCII AND NOT "VALID UTF-8". Windows PowerShell 5.1 - still the shell you
# get on a stock Windows install - reads a .ps1 with no byte-order mark as
# CP1252, one byte per character. A UTF-8 em-dash in a comment is three bytes,
# so 5.1 shows three garbage characters. Inside a comment that is only ugly; the
# moment one lands in a string, a path or a regex the script misbehaves in a way
# that has nothing to do with what the line looks like in the editor.
#
# The em-dash is the realistic way in, because every .md file in this repository
# uses them and these headers get copy-edited alongside the docs.
#
# Held as ASCII rather than fixed with a BOM on purpose: a BOM makes 5.1 read the
# file correctly and makes some other tooling read the BOM itself as content.
# ASCII needs no agreement from anybody.
const ASCII_HELPER_SCRIPTS := [
	"res://run_tests.ps1",
	"res://split_art.ps1",
	"res://atlasaudit.ps1",
]


func _test_helper_scripts_ascii() -> void:
	section("HELPER SCRIPTS — the .ps1 entry points are pure ASCII")

	for path in ASCII_HELPER_SCRIPTS:
		# Named one by one rather than discovered by scanning, so renaming or
		# deleting a documented entry point fails here instead of quietly
		# leaving the check with nothing to look at.
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			check("%s exists and is readable" % path.get_file(), false,
				"FileAccess said: %s" % error_string(FileAccess.get_open_error()))
			continue

		var offenders: Array[String] = []
		var line_no: int = 1
		for b in bytes:
			if b == 10:
				line_no += 1
			elif b > 127:
				var note := "line %d: byte 0x%02X" % [line_no, b]
				if not offenders.has(note):
					offenders.append(note)
		check("%s is pure ASCII" % path.get_file(), offenders.is_empty(),
			", ".join(offenders.slice(0, 8)))

	print("  %d helper script(s) checked byte by byte" % ASCII_HELPER_SCRIPTS.size())


# =============================================================================
# THE FLOOR COVERAGE BUDGET
# =============================================================================
# How much of the boss room is standing hazard at once. bossenemy.gd's
# PUDDLE_CHANCE comment holds the reasoning: a 65-pillar cast every 2.16s with a
# 2.5s pool would carpet 44% of the room, which is a fight you cannot read, and
# the constants exist to hold the real figure far below that.
#
# WHAT MAKES IT EASY TO GET WRONG IS THE SQUARE. Area goes as scale squared, so
# a pool scaled 1.25 covers 1.56x the floor, not 1.25x. That is why ice needs a
# 0.8 chance multiplier and water needs 0.5 to pay for its extra: 2 - both are
# compensation, and both say so in their own comment.
#
# THE INPUTS ARE SPREAD ACROSS TWELVE FILES: PUDDLE_CHANCE here, the per-element
# multiplier and `extra` in bossprojectile.gd's ELEMENT_PROFILE, puddle_life_scale
# beside them, and a lifetime and a scale authored into each of the nine
# <element>puddle.tscn files. Any one of those can be edited alone, and the only
# thing that noticed was a reader willing to redo the arithmetic.
#
# THE CEILING IS 30%, not the 23% the worst element currently sits at. A check
# pinned to today's number fails on every deliberate tuning pass and gets
# switched off; this one only fires when something has genuinely drifted toward
# the unreadable-floor case the whole budget exists to prevent.

const FLOOR_COVERAGE_CEILING := 0.30

# The unscaled pool. Every <element>puddle.tscn sizes its own shape from this:
# ice 11.25, earth 12.15, wind 7.2, and so on.
const PUDDLE_BASE_RADIUS := 9.0


func _test_floor_coverage() -> void:
	section("FLOOR COVERAGE — how much of the boss room is hazard at once")

	var pillars: float = 65.0
	var cast_interval: float = 2.16
	# Calibration from the PUDDLE_CHANCE comment: those pillars, that interval,
	# a 2.5s pool at scale 1 and chance 1 is the 44% case. Everything below is
	# measured against it rather than against a room size nobody wrote down.
	var unit_area: float = 0.44 / (pillars * (2.5 / cast_interval))

	var boss_script: Script = require_script(
		"res://src/projectiles/bossprojectile.gd", "the boss projectile")
	if boss_script == null:
		return
	var consts: Dictionary = boss_script.get_script_constant_map()
	var profile: Dictionary = consts.get("ELEMENT_PROFILE", {})
	check("the element profile table is readable", not profile.is_empty())
	if profile.is_empty():
		return

	var probe: Node = (load("res://scene/projectiles/bossprojectile.tscn") as PackedScene).instantiate()
	var life_scale: float = float(probe.puddle_life_scale)
	var base_chance: float = float(probe.puddle_chance)
	probe.free()

	var over: Array[String] = []
	var worst: float = 0.0
	var worst_name: String = ""

	for element in profile:
		var p: Dictionary = profile[element]
		var scene: PackedScene = Puddles.scene_for(int(element))
		if scene == null:
			continue
		var pool: Node = scene.instantiate()
		var life: float = float(pool.lifetime)
		# THE COLLISION RADIUS, NOT THE SPRITE SCALE. Hazard is what damages
		# you, and this project deliberately scales the sprite while sizing the
		# shape - the root Area2D stays at scale 1 on every puddle, so reading
		# node.scale here measured nothing at all. Today the two agree (every
		# radius is 9.0 x its sprite scale); reading the shape means they do not
		# have to, and a puddle that looks small while hitting big is caught
		# rather than assumed away.
		var radius: float = PUDDLE_BASE_RADIUS
		var shape_node: CollisionShape2D = pool.get_node_or_null("collisionshape2d")
		if shape_node != null and shape_node.shape is CircleShape2D:
			radius = float((shape_node.shape as CircleShape2D).radius)
		pool.free()

		var chance: float = base_chance * float(p.get("puddle", 1.0))
		var pools: float = 1.0 + float(p.get("extra", 0))
		# SQUARED - the trap this whole check exists for. Area goes as the
		# square of the radius, so a 1.25x pool is 1.56x the floor.
		var area_factor: float = (radius / PUDDLE_BASE_RADIUS) * (radius / PUDDLE_BASE_RADIUS)
		var coverage: float = pillars * chance * pools * area_factor \
			* ((life * life_scale) / cast_interval) * unit_area

		var label: String = str(Element.NAMES.get(int(element), element))
		if coverage > worst:
			worst = coverage
			worst_name = label
		if coverage > FLOOR_COVERAGE_CEILING:
			over.append("%s covers %.0f%% of the room (ceiling %.0f%%)"
				% [label, coverage * 100.0, FLOOR_COVERAGE_CEILING * 100.0])

	over.sort()
	check("no element carpets the boss room", over.is_empty(),
		"\n         ".join(over))
	check("and the worst is still well under the 44 percent unreadable case",
		worst < 0.44, "%s at %.1f%%" % [worst_name, worst * 100.0])

	print("  worst element: %s at %.1f%% of the floor" % [worst_name, worst * 100.0])


# =============================================================================
# ELEMENT.TYPE IS APPEND-ONLY, and this is what enforces it
# =============================================================================
# An enum value is written into a .tres as a BARE INTEGER. `element = 3` means
# ICE only because ICE is fourth. Insert a value anywhere but the end and every
# .tres, every .tscn and every saved game silently means something different -
# a fire enemy becomes a water one, and nothing errors, because 3 is still a
# perfectly valid integer.
#
# THE TABLE BELOW IS DELIBERATELY WRITTEN OUT rather than derived from the enum.
# Deriving it would make the check agree with whatever the enum currently says,
# which is precisely the thing under test. These are the numbers already baked
# into the data files on disk; the enum has to keep matching them, not the other
# way round.
#
# APPENDING IS FINE and stays green: a new member takes the next free integer
# and no existing file changes meaning. That is the whole rule, and this check
# permits exactly it.


func _test_element_enum_order() -> void:
	section("ELEMENT ENUM — append-only, because .tres stores bare integers")

	# name -> the integer the data files on disk already mean by it
	var baked := {
		"NONE": 0, "DARK": 1, "LIGHT": 2, "ICE": 3, "WIND": 4,
		"EARTH": 5, "FIRE": 6, "WATER": 7, "LIGHTNING": 8, "POISON": 9,
	}

	var wrong: Array[String] = []
	for element_name in baked:
		var want: int = int(baked[element_name])
		if not Element.Type.has(element_name):
			wrong.append("%s is gone from the enum (data files still say %d)" % [element_name, want])
			continue
		var got: int = int(Element.Type[element_name])
		if got != want:
			wrong.append("%s is now %d, but every .tres that says %d means %s"
				% [element_name, got, want, element_name])
	wrong.sort()

	check("every element still has the integer the data files were written with",
		wrong.is_empty(), "\n         ".join(wrong))

	# An append is legal; anything that shortens the enum is not.
	check("the enum has not lost members",
		Element.Type.size() >= baked.size(),
		"%d now, %d baked into data" % [Element.Type.size(), baked.size()])

	print("  %d elements pinned; appending a new one keeps this green" % baked.size())


# =============================================================================
# SCRIPT REFERENCES - the break that produces no error
# =============================================================================
# A .tscn or .tres saved by the editor names its script TWICE: uid="uid://..."
# and path="res://...". Godot resolves the uid first, so moving the script (with
# its .gd.uid) is safe.
#
# A HAND-AUTHORED ONE HAS ONLY THE PATH. Move that script and nothing errors:
# the resource loads, the script is simply absent, and the object falls back to
# its base class. Every class quietly running on Node's defaults is what that
# looks like from the outside, and it is invisible until someone plays the part
# of the game that needed it.
#
# So this walks every scene and resource, finds the references carrying no uid,
# and asserts the file each one names still exists. It cannot stop a script from
# moving; it makes the move loud instead of silent, which is the whole ask.


func _test_script_references() -> void:
	section("SCRIPT REFERENCES — path-only, and therefore fragile")

	var with_uid: int = 0
	var path_only: Array[String] = []
	var broken: Array[String] = []

	for root in ["res://scene", "res://data"]:
		_scan_script_refs(root, path_only, broken, [with_uid])

	# Recount properly: the int above cannot be passed by reference in GDScript,
	# so the scan returns totals through the arrays it fills instead.
	check("the project still contains script references to check",
		not path_only.is_empty() or not broken.is_empty(), path_only.size())

	# THE ONE THAT MATTERS. A path-only reference to a file that no longer
	# exists is a silently scriptless object.
	broken.sort()
	check("every path-only script reference resolves", broken.is_empty(),
		"\n         ".join(broken))

	print("  %d path-only references, across %d distinct scripts"
		% [path_only.size(), _distinct_scripts(path_only)])


func _scan_script_refs(dir_path: String, path_only: Array[String],
		broken: Array[String], _counter: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_script_refs(full, path_only, broken, _counter)
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			var text := FileAccess.get_file_as_string(full)
			for line in text.split("\n"):
				if not line.contains("type=\"Script\""):
					continue
				if line.contains("uid="):
					continue
				var from: int = line.find("path=\"")
				if from < 0:
					continue
				from += 6
				var to: int = line.find("\"", from)
				if to < 0:
					continue
				var script_path: String = line.substr(from, to - from)
				path_only.append("%s -> %s" % [full, script_path])
				if not ResourceLoader.exists(script_path):
					broken.append("%s names %s, which does not exist" % [full, script_path])
		entry = dir.get_next()
	dir.list_dir_end()


func _distinct_scripts(refs: Array[String]) -> int:
	var seen := {}
	for r in refs:
		seen[r.get_slice(" -> ", 1)] = true
	return seen.size()


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
		# `lost` IS IN THE SYNTHETIC ROWS so the measurement covers what the
		# panel actually does. It builds a second tooltip string per row, and a
		# per-row cost left out of the benchmark is a per-row cost nobody has
		# measured. Every third player, so both branches are exercised.
		rows.append({"username": "player%04d" % i, "contributed": 1_000_000 - i,
			"lusions": i, "deaths": i % 50, "rank": i + 1,
			"lost": (1_000_000 - i) / 2 if i % 3 == 0 else 0})

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
	# HEARTBEAT_SECONDS WAS IN THIS SUM AND IT SHOULD NOT HAVE BEEN. Nothing
	# fires Api.heartbeat() on a timer - the only caller is the 401 handler -
	# so this was charging every player a request per fifteen seconds that was
	# never sent. The budget was pessimistic by 0.067 req/s, which is harmless;
	# the arithmetic being about an imaginary request is not, because this sum
	# is the thing that decides whether a new panel's poll is affordable.
	#
	# The broadcast poll carries the beat now (app.py, stamp_presence), and it
	# is already counted below.
	var always: float = (
		1.0 / load("res://src/ui/characterhud.gd").BROADCAST_POLL_SECONDS
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


# =============================================================================
# CHECKS THAT NEED THE PRIVATE ART PACK
# =============================================================================
# art/pack/ is a private submodule holding purchased Clockwork Raven art. A clone
# of the PUBLIC repository cannot have it, by design and by licence - those files
# may be used in this game and not redistributed.
#
# WHY A SKIP AND NOT A FAILURE. Measured on a clone with the pack removed, this
# suite reported 12 failures and did not run 20 further checks. Every one of those
# was the licence boundary working exactly as intended, and all of it read as a
# broken project. Cloning a repository and running its tests is close to the first
# thing anybody evaluating it does, so that output is the project's first
# impression, and "12 failed" and "12 skipped, private art pack not present" are
# the same fact told two ways - one of which is true.
#
# It also has to stay honest in the other direction: on a machine that HAS the
# pack, every one of these runs and fails loudly, so a genuinely missing or
# renamed icon is still caught by the people who can see it. A skip that could
# hide a real defect from the author would be worse than a confusing report.
#
# NOT the same thing as the compile check's problem. kingdomboard.gd used to
# preload() two of these files, which made the whole script fail to COMPILE
# without the pack - that was a real defect and it was fixed rather than skipped.
# Skipping is only for facts that genuinely cannot be known without the art.
func _pack_present() -> bool:
	# The submodule directory exists but is empty in a clone that never ran
	# `git submodule update`, so the test is for a FILE, not the folder - the same
	# reasoning as the empty-folder rule in the art licensing check.
	return ResourceLoader.exists("res://art/pack/currency/goldpile.png")


func check_needs_pack(label: String, condition: bool, detail: Variant = "") -> void:
	"""check(), unless the private art pack is absent - then it is a skip."""
	if not _pack_present():
		# THE REASON TRAVELS WITH THE LABEL, because the summary at the end no
		# longer supplies one for the whole list - see _report().
		skipped += 1
		skips.append("%s   (private art pack not present; it holds purchased "
			% label + "art that may not be redistributed - see assetlicense.md)")
		_say("  skip  %s   (private art pack not present)" % label)
		return
	check(label, condition, detail)


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
	_check_no_script_errors()
	_say("")
	_say("=".repeat(60))
	if skipped > 0:
		_say("  %d passed, %d failed, %d skipped" % [passed, failed, skipped])
	else:
		_say("  %d passed, %d failed" % [passed, failed])
	if failed > 0:
		_say("")
		_say("  failing checks:")
		# `label`, not `name` - Node.name exists and shadowing it warns at parse.
		for label in failures:
			_say("    - " + label)
	if skipped > 0:
		_say("")
		# EACH SKIP CARRIES ITS OWN REASON NOW, and it had to.
		#
		# This block used to say "skipped — the private art pack is not
		# present. These need purchased art that may not be redistributed" over
		# EVERY skip, because for a long time there was only one kind. The
		# first skip from somewhere else - the empty sound registry - was
		# therefore reported as a licensing matter, which is not true and is
		# the sort of untrue that gets believed: it is in the summary, in bold
		# type, at the end of a green run.
		#
		# A summary that explains a list it does not actually know the contents
		# of is a comment with a number in front of it.
		_say("  skipped — each with its reason:")
		for label in skips:
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
	check_needs_pack("the small gold item exists", ItemRegistry.has_item(BaseEnemy.GOLD_SMALL_ID),
		BaseEnemy.GOLD_SMALL_ID)
	check_needs_pack("the large gold item exists", ItemRegistry.has_item(BaseEnemy.GOLD_LARGE_ID),
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
		check_needs_pack("the '%s' coin exists" % String(item_id),
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

	# TWO HAND-KEPT COPIES OF ONE NUMBER, now checked rather than hoped for.
	#
	# SKILL_XP_BASE is declared in PlayerStats and again in GameConstants, and
	# the two serve different callers: xp_needed_for_skill() takes the
	# PlayerStats value as a default argument because defaults are part of a
	# public signature, while xp_needed_for_skill_id() reads the GameConstants
	# one because that is the copy the exporter sends to the server.
	#
	# Both are deliberate. Nothing checked they agreed, which is precisely the
	# shape player.gd's own note calls "the exact shape of the bug this project
	# has already paid for once" - the character XP formula in two places, the
	# sanitizer rewriting honest saves, 1,636 XP becoming 52 million at level
	# 20. A divergence here would have surfaced as a confusing "skill level 1
	# costs the base" failure; this names it instead.
	check("both copies of SKILL_XP_BASE agree",
		PlayerStats.SKILL_XP_BASE == GameConstants.SKILL_XP_BASE,
		"PlayerStats %d, GameConstants %d"
			% [PlayerStats.SKILL_XP_BASE, GameConstants.SKILL_XP_BASE])

	# THE TWO CURVES ARE TUNED SEPARATELY NOW, and this check used to say the
	# skill curve must be the steeper one ("six skills compete for the same play
	# time"). The character curve became 1,250 x 1.27 for the eight hours to
	# level 22, and the skill curve was deliberately left alone: enemy skill XP
	# was scaled with enemy health, so skill XP per second of fighting is what it
	# was. Comparing the two growth rates stopped meaning anything the day one of
	# them was set by a pacing plan. What still must not happen is either one
	# moving by accident, so both are pinned; _test_the_game_has_a_pace holds
	# what the character curve is FOR.
	check("the character curve is the one the pacing plan set (1,250 x 1.27)",
		is_equal_approx(GameConstants.XP_BASE, 1250.0) and is_equal_approx(GameConstants.XP_GROWTH, 1.27),
		"%s x %s" % [GameConstants.XP_BASE, GameConstants.XP_GROWTH])
	check("the skill curve is unchanged by it (100 x 1.18)",
		PlayerStats.SKILL_XP_BASE == 100 and is_equal_approx(PlayerStats.SKILL_XP_FACTOR, 1.18),
		"%s x %s" % [PlayerStats.SKILL_XP_BASE, PlayerStats.SKILL_XP_FACTOR])

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
		check_needs_pack("a stackable item exists to test with", false,
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
		"damage_numbers": "damagenumbers",   "chat_filter": "chatfilter",
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
	check_needs_pack("every pin icon the map names exists", missing_art.is_empty(), missing_art)

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
# EVERY AREA CAN BE WALKED: you arrive clear of the doors, the walls hold, and
# every door can be walked to
# =============================================================================
# Found by walking the real game from the town gate to the Crowned and back.
# The boss room - the finale - failed both halves at once:
#
#   - its arrival marker had never been moved off (0, 0), which is where its
#     ladder UP stands. The arena's victory door put the winner on the exit, and
#     the ladder sent them straight back to the field. The last fight in the game
#     could not be reached.
#   - its tiles had no collision at all. The room's TileSet uses the same
#     underground sheet as the arena, and the arena's copy carries the wall
#     shapes; the boss room's copy had none, so a player walked off the corridor
#     into the black and kept going.
#
# Neither needs a player to see, so neither was seen: the BOSS ARENA section
# above checks that the marker EXISTS, and a marker at (0, 0) exists.
#
# HOW IT WALKS. Each area is instanced but never entered - no _ready, no player,
# no HUD, no requests. What it collides with is copied into a bare holder in the
# tree: every TileMapLayer (its tile_set and tile_map_data, so the tile shapes
# are the real ones) and every StaticBody2D with its shapes. A probe body wearing
# the warrior's own foot circle and collision mask then floods outward from every
# place a player arrives, a step at a time with test_move(). A spot whose feet
# touch a door counts as leaving and goes no further; an in-area teleporter hops
# to its destination. Nothing here is typed from the maps: the doors, markers,
# tiles and walls are read off the scenes, so a new door or a repainted room is
# checked the day it is saved.

# Four pixels, not a tile: the feet are 14 across, so a one-tile hole in a wall
# is a two-pixel window for them, and an 8px step walked straight past one.
# Measured: a hole a tile high still hides between even these steps (the feet
# have to be exactly aligned to fit), and a hole two tiles high is caught. The
# whole suite takes about sixteen seconds with this.
const WALK_STEP := 4.0
# How far past the painted map the flood may go before it counts as escaping.
const WALK_BOUND_MARGIN := 160.0
const DOOR_SCRIPTS := ["res://src/world/ladder.gd", "res://src/world/leavetown.gd",
	"res://src/world/victoryteleporter.gd", "res://src/world/teleporter.gd"]


# =============================================================================
# THE BIG FIELD
# =============================================================================
# Day 2: the owner wanted the Field twice the size, packed with enemies, "super
# fast and easy for players to jump into". bigfield.tscn is generated from the
# blueprint the owner signed off: the Field's own crypt tiles, a main road from
# the arrival to the ladder, ten fields off it, one element each, harder the
# further you go. These hold what the blueprint promised; the walk test above
# holds the walls and the doors, because bigfield is in AreaRegistry.AREAS.
const BIG_FIELD := "res://scene/bigfield.tscn"
const BIG_FIELD_BANDS := {"light": 1, "wind": 1, "water": 2, "ice": 2, "earth": 3,
	"electric": 3, "poison": 3, "bushmage": 3, "bushsniper": 3, "fire": 4, "dark": 5}

func _test_the_big_field() -> void:
	section("THE BIG FIELD - packed fields off one road, harder the further you go")

	check("it is an area: /goto and the walk test can reach it",
		AreaRegistry.has_area("bigfield") and str(AreaRegistry.AREAS.get("bigfield", "")) == BIG_FIELD
		and AreaRegistry.display_name("bigfield") == "Big Field")
	var packed: PackedScene = load(BIG_FIELD) as PackedScene
	check("it loads", packed != null)
	if packed == null:
		return
	var area: Node = packed.instantiate()
	var ground: TileMapLayer = area.get_node_or_null("ground") as TileMapLayer
	var arrival: Node2D = area.get_node_or_null("ysortworld/interactables/fieldteleport/arrivalmarker") as Node2D
	var enemies: Array = area.get_node("ysortworld/enemies").get_children() if area.has_node("ysortworld/enemies") else []
	check("the floor is painted from the Field's own crypt atlas",
		ground != null and ground.get_used_cells().size() > 10000
		and (ground.tile_set.get_source(1) as TileSetAtlasSource).texture.resource_path == "res://art/tiles/underground.png",
		ground.get_used_cells().size() if ground else 0)
	check("players arrive where the town's portal sends them (field_entrance)",
		arrival != null and str(arrival.get("portal_id")) == "field_entrance")
	var ladder: Node = area.get_node_or_null("ysortworld/interactables/ladderdown")
	check("the ladder at the far end goes down to the boss arena",
		ladder != null and str(ladder.get("destination_scene_path")) == "res://scene/bossarena.tscn")
	check("a respawner brings the fields back", area.get_node_or_null("enemyrespawner") != null)
	check("128 enemies are placed", enemies.size() == 128, enemies.size())

	# Positions are read relative to the area root, as the scene file holds them.
	var arrive_at: Vector2 = Vector2.ZERO
	if arrival != null:
		arrive_at = (arrival.get_parent() as Node2D).position + (arrival.get_parent() as Node2D).transform.basis_xform(arrival.position)
	var too_close: Array = []
	var in_walls: Array = []
	var chase: Array = []
	var by_band: Dictionary = {}
	for enemy in enemies:
		var at: Vector2 = (enemy as Node2D).position
		if at.distance_to(arrive_at) < 400.0:
			too_close.append(enemy.name)
		var cell: Vector2i = ground.local_to_map(at)
		var atlas: Vector2i = ground.get_cell_atlas_coords(cell)
		if not (atlas.x >= 1 and atlas.x <= 4 and atlas.y >= 1 and atlas.y <= 3):
			in_walls.append("%s on %s" % [enemy.name, atlas])
		if not is_equal_approx(float(enemy.get("leash_range")), 250.0):
			chase.append(enemy.name)
		var kind: String = str(enemy.scene_file_path).get_file().get_basename()
		var band: int = 0
		for prefix in BIG_FIELD_BANDS:
			if kind.begins_with(prefix):
				band = int(BIG_FIELD_BANDS[prefix])
				break
		if not by_band.has(band):
			by_band[band] = []
		by_band[band].append(at.x)
	check("a safe landing: nothing within 400 px of where players arrive", too_close.is_empty(), too_close)
	check("every enemy stands on open floor, none in a wall tile", in_walls.is_empty(), in_walls.slice(0, 4))
	check("every enemy chases from 250 px, so one field does not pull the next", chase.is_empty(), chase.slice(0, 4))
	var means: Array = []
	for band in [1, 2, 3, 4, 5]:
		var xs: Array = by_band.get(band, [])
		var total: float = 0.0
		for x in xs:
			total += float(x)
		means.append(total / maxf(xs.size(), 1.0))
	check("every enemy is in a band, and every band has its fields", not by_band.has(0)
		and [1, 2, 3, 4, 5].all(func(b): return by_band.has(b)), by_band.keys())
	check("harder the further you go: each band sits further along the road than the one before",
		means[0] < means[1] and means[1] < means[2] and means[2] < means[3] and means[3] < means[4], means)
	var kinds: Array = []
	for enemy in enemies:
		if not kinds.has(enemy.scene_file_path):
			kinds.append(enemy.scene_file_path)
	area.free()

	# The 250 above is what the scene file says. What counts is the number an
	# enemy chases from once it is in the world: bushmage.gd used to set its
	# own 1,500 in _ready(), after the scene's value, and the file check above
	# passed while every mage in the Big Field crossed the map.
	var holder := Node2D.new()
	holder.position = Vector2(-20000, -20000)
	add_child(holder)
	var placed: Array = []
	for i in kinds.size():
		var one: Node2D = (load(kinds[i]) as PackedScene).instantiate() as Node2D
		one.set("leash_range", 250.0)
		one.position = Vector2(i * 300, 0)
		holder.add_child(one)
		placed.append(one)
	var mage: Node2D = (load("res://scene/enemy/bushmage.tscn") as PackedScene).instantiate() as Node2D
	mage.position = Vector2(0, 600)
	holder.add_child(mage)
	await get_tree().process_frame
	await get_tree().process_frame
	var moved: Array = []
	for one in placed:
		if not is_equal_approx(float(one.get("leash_range")), 250.0):
			moved.append("%s %s" % [str(one.scene_file_path).get_file(), one.get("leash_range")])
	check("  and still 250 once each kind is in the world (%d kinds)" % kinds.size(), moved.is_empty(), moved)
	check("  while a mage nobody set still commits to the chase, as in the Field",
		is_equal_approx(float(mage.get("leash_range")), 1500.0), mage.get("leash_range"))
	holder.free()
	print("  128 enemies, bands along the road at x %s" % [means.map(func(m): return int(m))])


# =============================================================================
# FAR ENEMIES SLEEP
# =============================================================================
# Every enemy used to think on every physics tick wherever the player was. The
# Big Field holds 128, so enemysleeper.gd (added to every area by AreaRegistry)
# disables the ones more than SLEEP_DISTANCE away and wakes them inside
# WAKE_DISTANCE. Measured in the Big Field: 87 of 128 asleep where you arrive,
# physics 2.1 ms a frame against 3.3 with the sleeper off.
func _test_far_enemies_sleep() -> void:
	section("FAR ENEMIES SLEEP - beyond 1100 px an enemy stops thinking, inside 900 it wakes")

	var Sleeper := preload("res://src/world/enemysleeper.gd")
	var holder := Node2D.new()
	add_child(holder)
	var player := Node2D.new()
	player.add_to_group("player")
	holder.add_child(player)
	var near := Node2D.new(); near.position = Vector2(500, 0)
	var far := Node2D.new(); far.position = Vector2(1500, 0)
	var boss := Node2D.new(); boss.position = Vector2(1500, 300)
	for e in [near, far, boss]:
		e.add_to_group("enemies")
		holder.add_child(e)
	boss.add_to_group("unpushable")
	var sleeper: Node = Sleeper.add_to(holder)

	var asleep: int = sleeper.check_now()
	check("an enemy 1,500 px away sleeps", far.process_mode == Node.PROCESS_MODE_DISABLED and asleep == 1, asleep)
	check("  one 500 px away stays awake", near.process_mode == Node.PROCESS_MODE_INHERIT)
	check("  and a boss never sleeps", boss.process_mode == Node.PROCESS_MODE_INHERIT)

	# The welcome story freezes enemies with set_physics_process(false); the
	# sleeper must not undo that, nor be undone by it.
	far.set_physics_process(false)
	player.position = Vector2(450, 0)         # far 1,050 away: between the two
	sleeper.check_now()
	check("between 900 and 1,100 a sleeper stays asleep",
		far.process_mode == Node.PROCESS_MODE_DISABLED)
	player.position = Vector2(-500, 0)        # near 1,000 away, far 2,000
	sleeper.check_now()
	check("  and an awake one stays awake (no flicker at the edge)",
		near.process_mode == Node.PROCESS_MODE_INHERIT and far.process_mode == Node.PROCESS_MODE_DISABLED)
	player.position = Vector2(1300, 0)        # 200 from far
	sleeper.check_now()
	check("walking up wakes it", far.process_mode == Node.PROCESS_MODE_INHERIT and not far.has_meta(&"asleep"))
	check("  and waking leaves the story's own freeze alone", not far.is_physics_processing())
	far.set_physics_process(true)
	check("  the near one, now 800 px away, is still awake", near.process_mode == Node.PROCESS_MODE_INHERIT)

	player.position = Vector2(-2000, 0)
	sleeper.check_now()
	sleeper.enabled = false
	check("turning the sleeper off wakes everyone at once",
		near.process_mode == Node.PROCESS_MODE_INHERIT and far.process_mode == Node.PROCESS_MODE_INHERIT)
	check("  and while off it sleeps nobody", sleeper.check_now() == 0
		and far.process_mode == Node.PROCESS_MODE_INHERIT)

	var registry: String = _func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(")
	check("every area gets one when it opens (AreaRegistry._on_scene_changed)",
		registry.contains("EnemySleeper.add_to(scene)"))
	holder.free()

	# A respawn is a fresh copy of the enemy's scene; the chase range the Big
	# Field gives its monsters has to survive it.
	var Respawner := preload("res://src/world/enemyrespawner.gd")
	var arena := Node2D.new()
	add_child(arena)
	var light: Node2D = (load("res://scene/enemy/lightsprite.tscn") as PackedScene).instantiate()
	light.set("leash_range", 250.0)
	light.position = Vector2(-9000, -9000)
	arena.add_child(light)
	var respawner: Node = Respawner.new()
	respawner.spawn_scatter = 0.0
	arena.add_child(respawner)
	await get_tree().process_frame
	await get_tree().process_frame
	var entry: Dictionary = {}
	for e in respawner._census:
		if (e["position"] as Vector2).distance_to(Vector2(-9000, -9000)) < 1.0:
			entry = e
	check("the respawner's census keeps the chase range a scene set",
		float(entry.get("kept", {}).get("leash_range", 0.0)) == 250.0, entry.get("kept"))
	var before: int = arena.get_child_count()
	await respawner._respawn_after(entry, 0.0)
	var back: Node = arena.get_child(arena.get_child_count() - 1) if arena.get_child_count() > before else null
	check("  and the replacement chases from 250 too, not its scene's own 500",
		back != null and back != light and float(back.get("leash_range")) == 250.0,
		back.get("leash_range") if back else "nothing came back")
	arena.free()
	print("  sleep beyond %d px, wake inside %d px, every %.2f s"
		% [int(Sleeper.SLEEP_DISTANCE), int(Sleeper.WAKE_DISTANCE), Sleeper.CHECK_SECONDS])


func _test_every_area_can_be_walked() -> void:
	section("AREAS - you arrive clear of the doors, the walls hold, every door can be walked to")

	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	var feet_node: CollisionShape2D = warrior.get_node_or_null("bodyshape") as CollisionShape2D
	var feet: CircleShape2D = feet_node.shape as CircleShape2D if feet_node != null else null
	check("the player's feet are a circle this can stand in for", feet != null,
		"warrior.tscn bodyshape is not a CircleShape2D any more - the overlap maths below assumes one")
	if feet == null:
		warrior.free()
		return
	var feet_offset: Vector2 = feet_node.position
	var probe := CharacterBody2D.new()
	probe.collision_layer = 0
	probe.collision_mask = (warrior as CollisionObject2D).collision_mask
	var probe_shape := CollisionShape2D.new()
	probe_shape.shape = feet
	probe_shape.position = feet_offset
	probe.add_child(probe_shape)
	warrior.free()

	var walked: Array = []
	var skipped: Array = []
	for area_id in AreaRegistry.area_ids():
		var packed: PackedScene = load(AreaRegistry.AREAS[area_id]) as PackedScene
		if packed == null:
			check("%s loads" % area_id, false)
			continue
		var area: Node = packed.instantiate()
		var report: Dictionary = await _walk_area(area, probe, feet_offset, feet.radius)
		area.free()
		if report.is_empty():
			skipped.append(area_id)
			continue
		walked.append(area_id)

		check("%s: every arrival lands clear of every door" % area_id,
			report.landed_in.is_empty(), "arrives standing in a door: %s" % [report.landed_in])
		check("%s: the walls hold - nowhere a player can walk is off the map" % area_id,
			report.void_spots.is_empty() and not report.escaped,
			"%d spots with no tile under them%s, e.g. %s" % [report.void_spots.size(),
				" and it walked clean off the edge" if report.escaped else "", report.void_spots.slice(0, 4)])
		check("%s: every door can be walked to from where players arrive" % area_id,
			report.unreached.is_empty(), "never reached: %s" % [report.unreached])

	probe.free()
	check("the town, the field, the Big Field, the arena and the boss room were all walked",
		walked.has("elusion") and walked.has("field") and walked.has("bigfield") and walked.has("bossarena")
		and walked.has("boss"), walked)
	print("  walked %s; no map to walk in %s" % [walked, skipped])


func _walk_area(area: Node, probe: CharacterBody2D, feet_offset: Vector2, radius: float) -> Dictionary:
	# Empty when the area has no tiles at all - nothing to walk.
	var holder := Node2D.new()
	add_child(holder)
	var layers: Array = []
	for node in area.find_children("*", "TileMapLayer", true, false):
		var layer: TileMapLayer = node
		if layer.tile_map_data.size() <= 2:
			continue
		var copy := TileMapLayer.new()
		copy.tile_set = layer.tile_set
		copy.tile_map_data = layer.tile_map_data
		copy.collision_enabled = layer.collision_enabled
		copy.enabled = layer.enabled
		copy.transform = _area_xform(layer, area)
		holder.add_child(copy)
		layers.append(copy)
	if layers.is_empty():
		holder.free()
		return {}
	for node in area.find_children("*", "StaticBody2D", true, false):
		var wall: StaticBody2D = node
		var copy := StaticBody2D.new()
		copy.collision_layer = wall.collision_layer
		copy.transform = _area_xform(wall, area)
		for child in wall.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				copy.add_child(child.duplicate())
		holder.add_child(copy)
	holder.add_child(probe)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Doors that lead somewhere, and the in-area teleporters' hops.
	var doors: Array = []
	var hops: Array = []
	for script_path in DOOR_SCRIPTS:
		var found: Array = []
		_collect_by_script(area, script_path, found)
		for door in found:
			var rects: Array = _door_rects(door, area)
			if rects.is_empty():
				continue
			if script_path.ends_with("/teleporter.gd"):
				var to: Node = door.get_node_or_null("destinationpoint")
				if to != null:
					hops.append({"name": str(door.name), "rects": rects,
						"to": _area_xform(to, area).origin})
				continue
			if script_path.ends_with("/leavetown.gd") and door.get("destination_scene") == null:
				continue
			if script_path.ends_with("/ladder.gd") and str(door.get("destination_scene_path")) == "":
				continue
			doors.append({"name": str(door.name), "rects": rects})

	# Where players arrive: every FieldPortal marker, the town's playerspawn, and
	# the "player" container a player stands on when no marker is named.
	var starts: Array = []
	for node in area.find_children("*", "Node2D", true, false):
		if ("portal_id" in node and str(node.portal_id) != "") \
				or (node.name == "playerspawn" and node.get_parent() == area) \
				or (node.name == "player" and node.get_parent() != null and node.get_parent().name == "ysortworld"):
			starts.append({"name": str(node.get("portal_id")) if "portal_id" in node else str(node.name),
				"at": _area_xform(node, area).origin})

	var door_rects: Array = []
	for door in doors + hops:
		door_rects.append_array(door.rects)

	var landed_in: Array = []
	for start in starts:
		for door in doors + hops:
			if _feet_touch(start.at + feet_offset, radius, door.rects):
				landed_in.append("%s is in %s" % [start.name, door.name])

	var bound := Rect2()
	for i in layers.size():
		var layer: TileMapLayer = layers[i]
		var used: Rect2i = layer.get_used_rect()
		var box := layer.transform * Rect2(layer.map_to_local(used.position) - Vector2(layer.tile_set.tile_size) / 2.0,
			Vector2(used.size * layer.tile_set.tile_size))
		bound = box if i == 0 else bound.merge(box)
	bound = bound.grow(WALK_BOUND_MARGIN)

	var step := Vector2(WALK_STEP, WALK_STEP)
	var seen := {}
	var queue: Array = []
	for start in starts:
		var at: Vector2 = (start.at as Vector2).snapped(step)
		if not seen.has(at):
			seen[at] = true
			queue.append(at)
	var reached := {}
	var void_spots: Array = []
	var escaped := false
	var dirs := [Vector2(WALK_STEP, 0), Vector2(-WALK_STEP, 0), Vector2(0, WALK_STEP), Vector2(0, -WALK_STEP)]
	while not queue.is_empty():
		var at: Vector2 = queue.pop_back()
		var foot: Vector2 = at + feet_offset
		var leaving := false
		for door in doors:
			if _feet_touch(foot, radius, door.rects):
				reached[door.name] = true
				leaving = true
		for hop in hops:
			if _feet_touch(foot, radius, hop.rects):
				reached[hop.name] = true
				leaving = true
				var there: Vector2 = (hop.to as Vector2).snapped(step)
				if not seen.has(there):
					seen[there] = true
					queue.append(there)
		if leaving:
			continue
		# A gate is a sprite drawn over the ground, often over a hole in it, and
		# its trigger is smaller than its art: the town gate's step has no tile
		# under it. So a spot within one step of a door's edge is standing on the
		# door, not off the map.
		if not _tile_under(layers, foot) and not _feet_touch(foot, radius + WALK_STEP, door_rects):
			void_spots.append(at)
		for d in dirs:
			var next: Vector2 = at + d
			if seen.has(next):
				continue
			if not bound.has_point(next):
				escaped = true
				continue
			if probe.test_move(Transform2D(0.0, at), d):
				continue
			seen[next] = true
			queue.append(next)

	var unreached: Array = []
	for door in doors + hops:
		if not reached.has(door.name):
			unreached.append(door.name)
	holder.remove_child(probe)
	holder.free()
	return {"landed_in": landed_in, "void_spots": void_spots, "escaped": escaped,
		"unreached": unreached}


func _area_xform(node: Node, area: Node) -> Transform2D:
	# The node's transform in the area's own space, without the tree: every
	# Node2D from the area root down, multiplied. Nothing here has entered the
	# tree, so global_transform is not available.
	var xform := Transform2D.IDENTITY
	var at: Node = node
	while at != null:
		if at is Node2D:
			xform = (at as Node2D).transform * xform
		if at == area:
			break
		at = at.get_parent()
	return xform


func _door_rects(door: Node, area: Node) -> Array:
	var rects: Array = []
	for child in door.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null:
			rects.append(_area_xform(child, area) * (child as CollisionShape2D).shape.get_rect())
	return rects


func _feet_touch(centre: Vector2, radius: float, rects: Array) -> bool:
	for rect in rects:
		var r: Rect2 = rect
		var nearest := Vector2(clampf(centre.x, r.position.x, r.end.x), clampf(centre.y, r.position.y, r.end.y))
		if nearest.distance_to(centre) < radius:
			return true
	return false


func _tile_under(layers: Array, point: Vector2) -> bool:
	for node in layers:
		var layer: TileMapLayer = node
		if layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) != -1:
			return true
	return false


# =============================================================================
# THE FIELD'S WELCOME PLAYS ONCE A LOGIN
# =============================================================================
# field.gd played its opening narration - the welcome and the credits - on
# every arrival in the field, and the field is arrived in from the town gate,
# the boss room's ladder, a revive and a staff teleport. Walking up from the
# Crowned put the welcome on screen again, and every death in the field replayed
# it after the revive. GameState.opening_story_told keeps it to once a login,
# and CharacterData.clear_current_user(), which every login and logout runs,
# puts it back. It still has to play once: the credits are on it.

func _test_the_welcome_plays_once_a_login() -> void:
	section("THE FIELD'S WELCOME - once a login, not on every arrival")

	check("GameState remembers whether this login has heard it",
		"opening_story_told" in GameState)

	var field: String = FileAccess.get_file_as_string("res://src/world/field.gd")
	var ready_at: int = _first_code_index(field, "func _ready(", 0)
	var ready_end: int = _first_code_index(field, "\nfunc ", ready_at + 1)
	var guard: int = _within(_first_code_index(field, "if GameState.opening_story_told:", ready_at), ready_end)
	var told: int = _within(_first_code_index(field, "GameState.opening_story_told = true", ready_at), ready_end)
	var freeze: int = _within(_first_code_index(field, "_freeze_enemies()", ready_at), ready_end)
	var story: int = _within(_first_code_index(field, "StoryScreen.new()", ready_at), ready_end)
	var skip: int = _within(_first_code_index(field, "return", guard), told) if guard != -1 else -1
	check("the field asks before it plays the welcome",
		guard != -1 and story != -1 and guard < story, "guard at %d, story at %d" % [guard, story])
	check("  and a login that heard it goes no further", skip != -1,
		"nothing returns between the question and the answer")
	check("  and playing it marks it heard",
		told != -1 and guard < told and told < story, "marked at %d" % told)
	check("  and the enemies are frozen only for a welcome that plays",
		freeze != -1 and guard < freeze, "freeze at %d" % freeze)

	var data: String = FileAccess.get_file_as_string("res://src/systems/characterdata.gd")
	var clear_at: int = _first_code_index(data, "func clear_current_user(", 0)
	var clear_end: int = _first_code_index(data, "\nfunc ", clear_at + 1)
	check("every login and logout puts it back",
		_within(_first_code_index(data, "GameState.opening_story_told = false", clear_at), clear_end) != -1)
	var load_at: int = _first_code_index(data, "func load_for_user(", 0)
	var load_end: int = _first_code_index(data, "\nfunc ", load_at + 1)
	check("  and a login runs that reset",
		_within(_first_code_index(data, "clear_current_user()", load_at), load_end) != -1)
	print("  the welcome plays on the first field arrival of a login, and not again until the next")


# =============================================================================
# CHARACTER SELECT - a line about each class, and deleting a character
# =============================================================================
# Both asked for on day 1. Every account has four fixed slots, one per class,
# and there was no way to start a class again; and nothing on the screen said
# what a class is before you picked it.
#
# The screen is instanced but not entered, so its buttons are real and nothing
# is sent anywhere. What needs the server - the delete itself - is the API's
# test_chardelete.py; here are the order of what the game does around it and
# what the player is shown.

func _test_a_character_can_be_deleted() -> void:
	section("CHARACTER SELECT - a line about each class, and Delete that asks first")

	var Select: Script = load("res://src/ui/menus/characterselect.gd") as Script
	for class_id in ["warrior", "mage", "tank", "healer"]:
		var line: String = Select.class_line(class_id)
		check("the %s has a line saying how it plays" % class_id,
			line.length() >= 20 and line.length() <= 64 and not line.contains("\n"), line)
	# Day 1: "mage has pillars that rise from the ground". The line said it
	# dropped stone spikes, which is not what the player watches the spell do.
	check("the mage's line says its pillars rise, as the spell does",
		Select.class_line("mage").begins_with("Pillars") and not Select.class_line("mage").contains("spikes"),
		Select.class_line("mage"))

	var screen: Control = (load("res://scene/ui/menus/characterselect.tscn") as PackedScene).instantiate()
	screen._build_slot_extras()
	screen._build_slot_extras()
	var grid: Node = screen.get_node(screen.GRID_PATH)
	var placed: bool = true
	var once: bool = true
	var narrow: bool = true
	for i in 4:
		var column: Node = grid.get_node("%s/vbox" % screen.SLOT_CLASSES[i])
		var line: Label = screen.class_lines[i]
		placed = placed and line != null and line.get_parent() == column \
			and line.get_index() == column.get_node("classname").get_index() + 1 \
			and line.text == Select.class_line(screen.SLOT_CLASSES[i])
		once = once and column.find_children("classline*", "", false, false).size() == 1
		narrow = narrow and line.custom_minimum_size.x <= 210.0 and line.autowrap_mode != TextServer.AUTOWRAP_OFF
	check("each line is under its class's name", placed)
	check("  built once, and by the screen itself", once
		and _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _ready(").contains("_build_slot_extras()"))
	check("  and it wraps inside the panel rather than widening all four", narrow)

	# ---- Delete, where Create was ----
	var kept: Array = CharacterData.character_slots.duplicate(true)
	CharacterData.character_slots = [{"character": "warrior", "level": 12, "gold": 1204}, null, null, null]
	screen.update_slot_labels()
	var buttons: Array = screen.delete_buttons
	check("an occupied slot offers Delete in place of Create",
		buttons[0].visible and not buttons[0].disabled and not screen.get_node("%createbutton1").visible,
		[buttons[0].visible, screen.get_node("%createbutton1").visible])
	check("  an empty one offers Create and no Delete",
		not buttons[1].visible and screen.get_node("%createbutton2").visible)
	var two: bool = true
	for i in 4:
		var shown: int = 0
		for child in buttons[i].get_parent().get_children():
			if child is Button and child.visible:
				shown += 1
		two = two and shown == 2
	check("  and every slot still has two buttons, so the panels keep their width", two)

	# ---- it asks ----
	screen._ask_delete(0)
	check("Delete asks first", screen.confirm_box != null and screen.confirm_box.visible)
	check("  naming the character", screen.confirm_title.text == "Delete your Warrior?", screen.confirm_title.text)
	var body: String = screen.confirm_body.text
	check("  and what goes with it, and what stays",
		body.contains("Level 12") and body.contains("1,204 gold") and body.contains("bank")
		and body.contains("cannot be undone"), body)
	check("  and it wants the name typed", screen.confirm_name.placeholder_text == "Type WARRIOR to delete it"
		and screen.confirm_delete_button.disabled, screen.confirm_name.placeholder_text)
	screen._on_confirm_name_changed("warr")
	var half: bool = screen.confirm_delete_button.disabled
	screen._on_confirm_name_changed("mage")
	var wrong: bool = screen.confirm_delete_button.disabled
	screen._on_confirm_name_changed("  Warrior ")
	check("half the name, or another name, does not arm it; the name in any case does",
		half and wrong and not screen.confirm_delete_button.disabled)
	screen._close_confirm()
	check("Keep it closes the question and forgets the slot",
		not screen.confirm_box.visible and screen._deleting_slot == -1)
	screen._ask_delete(1)
	check("an empty slot is not asked about", not screen.confirm_box.visible)
	screen._entering = true
	screen._ask_delete(0)
	check("  nor anything while the world is loading", not screen.confirm_box.visible)
	screen._entering = false
	check("a character with no gold is not said to have any",
		not screen.delete_warning({"level": 1, "gold": 0}).contains("gold"),
		screen.delete_warning({"level": 1, "gold": 0}))
	CharacterData.character_slots = kept
	screen.free()

	# ---- the order around the request ----
	var confirm: String = _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _confirm_delete(")
	var sent: int = confirm.find("await CharacterData.delete_character(")
	var guard: int = confirm.find("if not is_instance_valid(self) or not is_inside_tree():")
	var redrawn: int = confirm.find("update_slot_labels()")
	check("the box sends what was typed, and redraws the slots only if the screen is still there",
		sent != -1 and sent < guard and guard < redrawn, [sent, guard, redrawn])
	check("  and says the server's reason when it refuses", confirm.contains("res.get(\"error\""))
	var data: String = _func_body(_code_src("res://src/systems/characterdata.gd"), "func delete_character(")
	var flushed: int = data.find("await finish_saving()")
	var posted: int = data.find("Api.post(\"/api/character/delete\"")
	var refused: int = data.find("if not res.get(\"ok\", false):")
	var emptied: int = data.find("character_slots[slot_idx] = null")
	var forgot: int = data.find("storage.forget_slot(slot_idx)")
	check("CharacterData saves what is on its way before it asks the server to delete",
		flushed != -1 and flushed < posted, [flushed, posted])
	check("  and empties the slot only once the server said yes",
		posted < refused and refused < emptied and emptied != -1 and forgot > refused, [posted, refused, emptied, forgot])
	var select_src: String = _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _select_character(")
	check("a character cannot be picked while a delete is on its way",
		select_src.contains("if _entering or _deleting:"))

	# ---- a new character in the slot is pushed, not skipped ----
	var store := ServerStorage.new()
	for key in ["save:1", "status:1", "save:2", "lusions"]:
		store._last_pushed[key] = "pushed"
	store._failed_keys["status:1"] = true
	store.forget_slot(1)
	check("the storage forgets what it pushed for a deleted slot, so the next character there is sent",
		not store._last_pushed.has("save:1") and not store._last_pushed.has("status:1")
		and not store._failed_keys.has("status:1"),
		store._last_pushed)
	check("  and nothing about the other slots or the account",
		store._last_pushed.has("save:2") and store._last_pushed.has("lusions"))
	check("  by the same names its pushes use",
		ServerStorage._slot_keys(3) == store._slot_sections(3, {"character": "healer"}).map(
			func(section: Array) -> String: return section[0]))

	# ---- a character made again starts whole ----
	# Found by deleting and making a warrior live: the new character was pushed
	# with SAVEABLE_STATS' 100s, the server took that as damage from its 180,
	# and the full bars the game then drew were clamped as an unexplained heal.
	var whole: bool = true
	var seen: Array = []
	for class_id in ["warrior", "mage", "tank", "healer"]:
		var made: Dictionary = (load("res://src/systems/characterdata.gd") as GDScript).new_character(class_id)
		var cls: ClassData = load("res://data/classes/%s.tres" % class_id) as ClassData
		var ok: bool = cls != null and int(made["hp"]) == cls.hp_base and int(made["max_hp"]) == cls.hp_base \
			and int(made["mana"]) == cls.mana_base and int(made["max_mana"]) == cls.mana_base \
			and int(made["stamina"]) == cls.stam_base and int(made["max_stamina"]) == cls.stam_base
		whole = whole and ok
		seen.append("%s %s/%s" % [class_id, made["hp"], made["max_hp"]])
	check("a new character starts on its class's full pools, not a flat 100", whole, seen)
	check("  and Create makes it that way",
		_func_body(_code_src("res://src/systems/characterdata.gd"), "func create_character(")
			.contains("new_character(character_name)"))
	print("  character select: the class lines, Delete in Create's place, the question, and the order")


# =============================================================================
# STAFF LOGINS: ONE CODE PER COMPUTER
# =============================================================================
# A code on every staff login was the owner's own complaint the first day he
# had it. A login that got in with a code is answered with a device token
# (TRUSTED DEVICES in app.py, test_staffcode.py); the game keeps it per account
# and sends it with the next login from this computer.

func _test_one_code_per_computer() -> void:
	section("STAFF LOGINS - the code once per computer, not once per login")

	# The suite's own writes go in a copy it puts back afterwards.
	var kept: String = FileAccess.get_file_as_string(Api.DEVICES_PATH) \
		if FileAccess.file_exists(Api.DEVICES_PATH) else ""
	check("an account never proved on this computer has no device token",
		Api.device_token_for("nobody-proved-this") == "")
	Api._remember_device("  Warden ", "device-abc")
	check("a token kept for an account is found again, whatever case the name is typed in",
		Api.device_token_for("warden") == "device-abc" and Api.device_token_for("WARDEN") == "device-abc")
	Api._remember_device("keeper", "device-xyz")
	check("  each account keeps its own", Api.device_token_for("warden") == "device-abc"
		and Api.device_token_for("keeper") == "device-xyz")
	check("it is kept apart from the session, which Remember me and Log out throw away",
		Api.DEVICES_PATH != Api.SESSION_PATH
		and not _func_body(_code_src("res://src/systems/api.gd"), "func _clear_session(").contains("DEVICES_PATH"))

	var login_src: String = _func_body(_code_src("res://src/systems/api.gd"), "func login(")
	var sent: int = login_src.find("body[\"device\"] = device")
	var posted: int = login_src.find("await post(\"/api/auth/login\", body)")
	var adopted: int = login_src.find("_adopt_session(res.data)")
	var kept_at: int = login_src.find("_remember_device(user,")
	check("the login sends this computer's token with the password",
		sent != -1 and sent < posted, [sent, posted])
	check("  and keeps the one the server hands back, only on a login that got in",
		adopted != -1 and posted < adopted and adopted < kept_at, [posted, adopted, kept_at])

	if kept == "":
		DirAccess.remove_absolute(Api.DEVICES_PATH)
	else:
		var file := FileAccess.open(Api.DEVICES_PATH, FileAccess.WRITE)
		file.store_string(kept)
		file.close()
	print("  staff logins: a device token per account, apart from the session, sent and kept")


# =============================================================================
# THIS COPY OF THE GAME - the install id a ban follows through a VPN
# =============================================================================
# The server refuses a new account from a computer a banned account has used
# (INSTALL IDS in app.py, test_security.py E-5f). That only works if the game
# makes the id once, keeps it where logging out cannot reach it, and sends it
# on every way in.

func _test_install_id_is_kept_and_sent() -> void:
	section("INSTALL ID - one per computer, kept, sent on every way in")

	# The suite's own writes go in a copy it puts back afterwards.
	var kept: String = FileAccess.get_file_as_string(Api.INSTALL_PATH) \
		if FileAccess.file_exists(Api.INSTALL_PATH) else ""
	var was_cached: String = Api._install_id

	DirAccess.remove_absolute(Api.INSTALL_PATH)
	Api._install_id = ""
	var first: String = Api.install_id()
	check("a computer with no id is given one: 64 hex characters",
		first.length() == 64 and first.is_valid_hex_number(), first)
	check("  asking again gives the same one", Api.install_id() == first)
	Api._install_id = ""
	check("  and it comes back from the file after a restart", Api.install_id() == first)
	# On the script, not the autoload: it is static (STATIC_CALLED_ON_INSTANCE).
	var api_script: GDScript = load("res://src/systems/api.gd") as GDScript
	check("  each new computer gets its own", str(api_script.call("_fresh_install_id")) != first)

	var junk := ConfigFile.new()
	junk.set_value("install", "id", "not an id")
	junk.save(Api.INSTALL_PATH)
	Api._install_id = ""
	var mended: String = Api.install_id()
	check("a damaged file is replaced, not sent", mended != "not an id"
		and mended.length() == 64 and mended.is_valid_hex_number(), mended)

	var api_src: String = _code_src("res://src/systems/api.gd")
	check("it lives apart from the session, which Log out and Remember me throw away",
		Api.INSTALL_PATH != Api.SESSION_PATH and Api.INSTALL_PATH != Api.DEVICES_PATH
		and not _func_body(api_src, "func _clear_session(").contains("INSTALL_PATH"))
	check("the login sends it",
		_func_body(api_src, "func login(").contains("\"install\": install_id()"))
	check("  so does registering - the request the ban actually refuses",
		_func_body(api_src, "func register(").contains("\"install\": install_id()"))
	check("  and resuming a remembered login",
		_func_body(api_src, "func probe_and_resume(").contains(
			"post(\"/api/auth/resume\", {\"install\": install_id()}"))

	# The staff view says how two accounts are linked; "same computer" is the
	# half a VPN does not change, so it has to read as such.
	const OwnerPanelScript := preload("res://src/ui/owner/ownerpanel.gd")
	check("the staff view names a shared computer",
		OwnerPanelScript.linked_how({"shared_computers": 1}) == "same computer")
	check("  beside the addresses when there are both",
		OwnerPanelScript.linked_how({"shared_addresses": 2, "quietest_address_accounts": 3,
			"shared_computers": 1}) == "shares 2 addresses, quietest holds 3, same computer")
	check("  and how crowded the computer is, when it is",
		OwnerPanelScript.linked_how({"shared_computers": 1, "quietest_computer_accounts": 9})
			== "same computer, 9 accounts on it")
	check("  and an address-only link reads as it always did",
		OwnerPanelScript.linked_how({"shared_addresses": 1, "quietest_address_accounts": 2})
			== "shares 1 address, quietest holds 2")

	if kept == "":
		DirAccess.remove_absolute(Api.INSTALL_PATH)
	else:
		var file := FileAccess.open(Api.INSTALL_PATH, FileAccess.WRITE)
		file.store_string(kept)
		file.close()
	Api._install_id = was_cached
	print("  install id: made once, kept apart from the session, sent with login, register and resume")


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

func _test_a_window_never_outgrows_the_screen() -> void:
	section("OPTIONS - a window size bigger than the screen")
	# Called on the script, not the autoload: they are static.
	const SettingsScript := preload("res://src/systems/settings.gd")

	# Day 1: 2560x1440 picked on a smaller monitor put the window's title bar
	# off the top of the screen, Options with it, and the way back was editing
	# options.cfg by hand. A 1920x1080 screen with a taskbar and a title bar
	# has about 1904x1001 of room.
	var room := Vector2i(1904, 1001)
	check("a window too wide for the screen comes down to the widest size that fits",
		SettingsScript.fit_window_side(2560, room.x, 0) == 1600, SettingsScript.fit_window_side(2560, room.x, 0))
	check("  and one too tall to the tallest, which is the same size",
		SettingsScript.fit_window_side(1440, room.y, 1) == 900, SettingsScript.fit_window_side(1440, room.y, 1))
	check("  3840x2160 too",
		SettingsScript.fit_window_side(3840, room.x, 0) == 1600 and SettingsScript.fit_window_side(2160, room.y, 1) == 900)
	check("  a size that fits is left alone",
		SettingsScript.fit_window_side(1280, room.x, 0) == 1280 and SettingsScript.fit_window_side(1920, 2544, 0) == 1920)
	check("  a screen too small for any of them gets 1280x720, the smallest window the game allows",
		SettingsScript.fit_window_side(1600, 1350, 0) == 1280 and SettingsScript.fit_window_side(900, 700, 1) == 720)
	check("  and a screen that cannot be measured shrinks nothing",
		SettingsScript.fit_window_side(3840, 0, 0) == 3840
		and SettingsScript.window_fits(Vector2i(3840, 2160), Vector2i.ZERO))

	# THE FILE GOES THROUGH IT TOO, which is what fixes a window already saved
	# too big: the next launch reads options.cfg through _normalise(). This run
	# is headless and has no screen to measure, so the wiring is read instead.
	var source: String = (load("res://src/systems/settings.gd") as GDScript).source_code
	var normalise: String = source.substr(source.find("func _normalise("))
	normalise = normalise.substr(0, normalise.find("\nfunc ", 10))
	check("  a size read from options.cfg is shrunk to fit as it is read",
		normalise.contains("fit_window_side(int(typed), window_room().x, 0)")
		and normalise.contains("fit_window_side(int(typed), window_room().y, 1)"))

	# THE PICKER greys out what does not fit, and says why.
	var screen: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	screen.window_size = screen.get_node("%windowsize")
	screen._populate_window_sizes()
	screen._mark_window_sizes(room)
	var picker: OptionButton = screen.window_size
	var offered: Array = []
	var refused: Array = []
	for i in picker.item_count:
		(refused if picker.is_item_disabled(i) else offered).append(Settings.WINDOW_SIZES[i])
	check("Options offers only the sizes this screen has room for",
		offered == [Vector2i(1280, 720), Vector2i(1600, 900)], offered)
	check("  the rest are greyed out and say why",
		refused.size() == 3 and picker.get_item_text(4).ends_with("too big for this screen"),
		picker.get_item_text(4))
	screen._mark_window_sizes(Vector2i(7680, 4320))
	var all_back := true
	for i in picker.item_count:
		if picker.is_item_disabled(i) or picker.get_item_text(i).contains("too big"):
			all_back = false
	check("  and on a bigger screen they all come back", all_back)
	screen.free()


func _test_banked_gold_goes_through_the_server() -> void:
	section("BANK - gold is moved by the server, or not at all")

	# Day 1: banking 200 of 257 showed 57 carried and 200 banked, and the server
	# still held 257 carried and 0 banked. The two functions moved the numbers
	# on this machine and nothing ever called /api/bank/gold, so a relog put the
	# gold back in the purse and a death would have burned all of it.
	var holder := GDScript.new()
	holder.source_code = "extends Node\nvar gold: int = 257\nvar notices: Array = []\nfunc show_notice(m): notices.append(m)\n"
	holder.reload()
	var fake: Node = holder.new()
	var kept_bank: int = CharacterData.get_bank_gold()
	var kept_slot: int = CharacterData.active_character_index
	var kept_slots: Array = CharacterData.character_slots.duplicate(true)
	CharacterData.account_data["bank_gold"] = 0
	var asked: Array = []

	# A REFUSAL MOVES NOTHING, and says why.
	CharacterData.bank_gold_request = func(body: Dictionary) -> Dictionary:
		asked.append(body)
		return {"ok": false, "status": 400, "error": "Cannot deposit 200 - only 57 carried."}
	var moved: bool = await CharacterData.deposit_gold_to_bank(200, fake)
	check("a deposit asks the server, with the amount and the operation",
		asked.size() == 1 and asked[0].get("op") == "deposit" and int(asked[0].get("amount", 0)) == 200
			and asked[0].has("slot"), asked)
	check("  and when it refuses, neither the purse nor the bank moves",
		not moved and fake.gold == 257 and CharacterData.get_bank_gold() == 0,
		[moved, fake.gold, CharacterData.get_bank_gold()])
	check("  and the player is told why", fake.notices.size() == 1 and str(fake.notices[0]).contains("only 57"),
		fake.notices)

	# AN ANSWER IS COPIED, NOT ADDED UP. The server's two figures are what the
	# screen shows, even when they are not what this side would have worked out.
	CharacterData.bank_gold_request = func(body: Dictionary) -> Dictionary:
		asked.append(body)
		return {"ok": true, "status": 200, "data": {"carried_gold": 50, "bank_gold": 207}}
	moved = await CharacterData.deposit_gold_to_bank(200, fake)
	check("a deposit the server took shows the server's purse and bank",
		moved and fake.gold == 50 and CharacterData.get_bank_gold() == 207,
		[moved, fake.gold, CharacterData.get_bank_gold()])
	CharacterData.bank_gold_request = func(body: Dictionary) -> Dictionary:
		asked.append(body)
		return {"ok": true, "status": 200, "data": {"carried_gold": 80, "bank_gold": 177}}
	moved = await CharacterData.withdraw_gold_from_bank(30, fake)
	check("  and so does a withdrawal",
		moved and asked[-1].get("op") == "withdraw" and fake.gold == 80 and CharacterData.get_bank_gold() == 177,
		[asked[-1], fake.gold, CharacterData.get_bank_gold()])

	CharacterData.bank_gold_request = Callable()
	CharacterData.account_data["bank_gold"] = kept_bank
	CharacterData.active_character_index = kept_slot
	CharacterData.character_slots = kept_slots
	fake.free()
	print("  gold between the purse and the bank is the server's to move")


func _test_the_store_sells_the_next_set() -> void:
	section("SHOP - iron to amethyst on sale, a shelf per band")

	# Day 1, decided by the owner: the general store sells every weapon and
	# armour piece from iron to amethyst at its value, so a player farming one
	# band saves for the next band's set. Ember stays drop-only. Anyone may buy
	# any piece; the level gate is on wearing it (test_pacing.py holds that,
	# and the saving pace, against the real server).
	var store: ShopData = load("res://data/shops/generalstore.tres") as ShopData
	check("generalstore.tres loads as a ShopData", store != null)
	if store == null:
		return
	# THE REGISTRY NEEDS THE PACK: every item's icon is in art/pack, and an item
	# whose icon will not load is not registered. Without it these are skips.
	var stock: Array[String] = store.stock
	var missing: Array = []
	var too_good: Array = []
	var gear_seen := 0
	for item in ItemRegistry.get_all_items():
		if item.type != ItemData.Type.WEAPON and item.type != ItemData.Type.ARMOR:
			continue
		gear_seen += 1
		if item.tier >= 1 and item.tier <= 4 and not stock.has(item.item_id):
			missing.append(item.item_id)
		if item.tier >= 5 and stock.has(item.item_id):
			too_good.append(item.item_id)
	check_needs_pack("every weapon and armour piece of iron to amethyst is stocked",
		gear_seen > 0 and missing.is_empty(), missing)
	check_needs_pack("  and nothing of ember or above", too_good.is_empty(), too_good)
	var unknown: Array = stock.filter(func(id: String) -> bool: return not ItemRegistry.has_item(id))
	check_needs_pack("  every stocked id is a real item", unknown.is_empty(), unknown)
	check("  sold at its value", is_equal_approx(store.price_multiplier, 1.0), store.price_multiplier)

	# THE SERVER SELLS FROM gamedata.json, not from the .tres. An export that
	# was not re-run (or not copied across) leaves the server on the old shelf.
	var exported: Dictionary = {}
	for shop in _load_gamedata().get("shops", []):
		if shop is Dictionary and str(shop.get("shop_id", "")) == store.shop_id:
			exported = shop
	check("data/gamedata.json carries the same stock in the same order",
		Array(exported.get("stock", [])) == Array(stock), "re-run src/tools/exportgamedata.gd")

	# ONE SHELF PER BAND, which needs the stock in shelf order: show_catalogue()
	# starts a heading whenever the kind of row changes, so a tier that came
	# back after another would get a second heading. Read from the export, which
	# carries each item's type and tier without needing the art.
	var panel_script: GDScript = load("res://src/ui/shop/shopinventory.gd") as GDScript
	var exported_items: Dictionary = {}
	for row in _load_gamedata().get("items", []):
		if row is Dictionary:
			exported_items[str(row.get("item_id", ""))] = row
	var shelves: Array = []
	for id in stock:
		var shelf: String = panel_script.shelf_of(exported_items.get(id, {}))
		if shelves.is_empty() or shelves[-1] != shelf:
			shelves.append(shelf)
	check("the stock runs potions, fishing, then iron, jade, cobalt, amethyst, each once",
		shelves == ["supplies", "fishing", "gear 1", "gear 2", "gear 3", "gear 4"], shelves)

	# FISHING: the worm and every rod but ember, decided by the owner on day 1.
	# Only the iron rod could be had before, and worms dropped one at a time.
	var fishing: Array = stock.filter(func(id: String) -> bool:
		return panel_script.shelf_of(exported_items.get(id, {"item_id": id})) == "fishing")
	check("the fishing shelf has the worm and the iron to amethyst rods, and no ember rod",
		fishing == ["fishingworm", "ironfishingrod", "jadefishingrod", "cobaltfishingrod", "amethystfishingrod"],
		fishing)
	var pond: Node = (load("res://scene/interactables/fishingspot.tscn") as PackedScene).instantiate()
	check("  the shelf's bait is the pond's", panel_script.FISHING_BAIT_ID == str(pond.bait_item_id),
		pond.bait_item_id)
	pond.free()

	# THE LANDS ON A HEADING ARE THE LANDS THAT DROP THE TIER. Read off every
	# normal enemy, so moving an element to another band without updating
	# TIER_ELEMENTS fails here instead of sending players to the wrong place.
	var listed: Dictionary = {}
	for tier in GameConstants.TIER_ELEMENTS.size():
		for element in GameConstants.TIER_ELEMENTS[tier]:
			check("  %s is listed under one tier" % Element.name_for(int(element)), not listed.has(element))
			listed[element] = tier
	var wrong: Array = []
	var normals := 0
	var dir := DirAccess.open("res://data/enemies")
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null or enemy.slots_are_gear or not listed.has(enemy.element):
			continue
		normals += 1
		if enemy.max_loot_tier != listed[enemy.element]:
			wrong.append("%s drops tier %d, listed under %d" % [enemy.enemy_id, enemy.max_loot_tier, listed[enemy.element]])
	if normals == 0:
		wrong.append("no normal enemies were read")
	check("every normal enemy drops the tier its element is listed under", wrong.is_empty(), wrong)
	check("  tier 2 is the Water and Ice lands", GameConstants.tier_lands(2) == "Water and Ice",
		GameConstants.tier_lands(2))
	var named_ok := true
	for tier in range(1, GameConstants.TIER_MATERIALS.size()):
		var sword: Dictionary = exported_items.get(GameConstants.TIER_MATERIALS[tier].to_lower() + "sword", {})
		if int(sword.get("tier", -1)) != tier:
			named_ok = false
	check("  each tier's material names its sword", named_ok)

	# THE PANEL, drawn from an answer in the server's shape - the rows the
	# server builds from the same export.
	var panel: Node = (load("res://scene/ui/shop/shopinventory.tscn") as PackedScene).instantiate()
	panel.header_label = panel.get_node("%headerlabel")
	panel.stock_list = panel.get_node("%stocklist")
	panel.notice_label = panel.get_node("%noticelabel")
	var rows: Array = []
	for id in ["tinyhealthpotion", "fishingworm", "jadefishingrod", "ironsword", "ironhelm", "jadesword",
			"cobaltsword", "amethystsword"]:
		var item: Dictionary = exported_items.get(id, {})
		rows.append({"item_id": id, "display_name": str(item.get("display_name", id)),
			"price": int(item.get("value", 0)), "tier": int(item.get("tier", 1)),
			"type_name": str(item.get("type_name", "")), "required_level": int(item.get("required_level", 1)),
			"required_classes": []})
	panel.show_catalogue({"display_name": "General Store", "stock": rows})
	var headings: Array = []
	var row_count := 0
	for child in panel.stock_list.get_children():
		if child is Label:
			headings.append(child.text)
		else:
			row_count += 1
	check("the panel heads each shelf once, in order", headings == [
		"Potions and supplies",
		"Fishing  ·  rods and worms",
		"Iron  ·  the Light and Wind lands  ·  level 1",
		"Jade  ·  the Water and Ice lands  ·  level 5",
		"Cobalt  ·  the Earth lands  ·  level 10",
		"Amethyst  ·  the Fire lands  ·  level 16"], headings)
	check("  with every row under them", row_count == rows.size(), row_count)
	panel.show_catalogue({"display_name": "General Store", "stock": rows})
	check("  and drawing it again does not double it",
		panel.stock_list.get_child_count() == rows.size() + 6, panel.stock_list.get_child_count())
	panel.free()
	print("  the store sells the next set, and the shelf says where its band is")


func _test_founding_a_guild_shows_what_it_cost() -> void:
	section("GUILD - founding shows the purse and bank the server left")

	# Day 1: founding cost 5,000, paid 1,000 carried and 4,000 from the bank,
	# and the game went on showing 1,000 and 4,500 until a relog. The server
	# held 0 and 500; the panel read only the sentence out of its answer.
	var holder := GDScript.new()
	holder.source_code = "extends Node\nvar gold: int = 1000\nfunc set_gold(total: int) -> void:\n\tgold = total\n"
	holder.reload()
	var fake: Node = holder.new()
	add_child(fake)
	var others: Array = get_tree().get_nodes_in_group("player")
	fake.add_to_group("player")
	var kept_bank: int = CharacterData.get_bank_gold()
	CharacterData.account_data["bank_gold"] = 4500
	var panel: Control = (load("res://scene/ui/guild/guildpanel.tscn") as PackedScene).instantiate() as Control
	add_child(panel)
	var asked: Array = []
	panel.post_request = func(path: String, _body: Dictionary) -> Dictionary:
		asked.append(path)
		return {"ok": true, "status": 200, "data": {"guild": {}, "rank": "leader", "gold": 0,
			"carried_gold": 0, "bank_gold": 500, "paid": 5000, "from_carried": 1000, "from_bank": 4000}}
	await panel._act("/api/guild/create", {"name": "Day One", "slot": 0},
		"Day One is founded. You are its leader.")
	check("founding asks the server", asked == ["/api/guild/create"], asked)
	check("  the purse shows what the server left", others.is_empty() and fake.gold == 0, [others.size(), fake.gold])
	check("  and so does the bank", CharacterData.get_bank_gold() == 500, CharacterData.get_bank_gold())
	check("  and the notice says which pile paid",
		panel.notice.text.ends_with("1000 carried and 4000 from the bank."), panel.notice.text)

	fake.gold = 77
	panel.post_request = func(_path: String, _body: Dictionary) -> Dictionary:
		return {"ok": false, "status": 400, "error": "Founding a guild costs 5000 gold."}
	await panel._act("/api/guild/create", {"name": "Day Two", "slot": 0}, "founded")
	check("a refusal moves neither", fake.gold == 77 and CharacterData.get_bank_gold() == 500,
		[fake.gold, CharacterData.get_bank_gold()])
	panel.post_request = func(_path: String, _body: Dictionary) -> Dictionary:
		return {"ok": true, "status": 200, "data": {"invited": "caster"}}
	await panel._act("/api/guild/invite", {"username": "caster"}, "Invited caster.")
	check("  nor does an answer with no gold in it", fake.gold == 77 and CharacterData.get_bank_gold() == 500,
		[fake.gold, CharacterData.get_bank_gold()])

	# THE OWNER'S GOLD GRANT had the same half: the purse was copied, the bank was not.
	check("the owner's gold grant copies the bank as well as the purse",
		_func_body(_code_src("res://src/ui/owner/ownerpanel.gd"), "func _on_gold_pressed(")
			.contains("CharacterData.adopt_server_gold("))

	panel.free()
	fake.free()
	CharacterData.account_data["bank_gold"] = kept_bank
	print("  gold the server took for a guild shows at once")


func _test_a_request_waiting_on_you_lights_its_button() -> void:
	section("FRIENDS AND GUILD - a request waiting on you lights its button")

	# Day 1: a friend request or guild invitation to somebody standing next to
	# you sat unseen until they opened the panel. The poll carries `asks` now.
	var hud_script: Script = load("res://src/ui/characterhud.gd") as Script
	hud_script._forget_asks()
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	var rows: Control = hud.message_rows
	var friends_button: Button = hud.get_node("%friendsbutton") as Button
	var guild_button: Button = hud.get_node("%guildbutton") as Button
	var guild_tip: String = guild_button.tooltip_text
	var asks := func(friends: int, who: String, at: int, guilds: int, guild: String, g_at: int) -> Dictionary:
		return {"latest_id": 0, "messages": [], "asks": {
			"friends": {"count": friends, "newest": who, "at": at},
			"guild": {"count": guilds, "newest": guild, "at": g_at}}}
	var toasts := func() -> Array:
		var out: Array = []
		for child in rows.get_children():
			out.append((child as Label).text)
		return out

	hud._apply_broadcast(asks.call(0, "", 0, 0, "", 0))
	check("nothing waiting: the buttons read as they always did",
		friends_button.text == "Friends" and guild_button.text == "Guild" and rows.get_child_count() == 0,
		[friends_button.text, guild_button.text])
	hud._apply_broadcast(asks.call(1, "caster", 1000, 0, "", 0))
	check("a friend request lights Friends", friends_button.text == "Friends •", friends_button.text)
	check("  says who is waiting", friends_button.tooltip_text == "caster is waiting on your answer",
		friends_button.tooltip_text)
	check("  and is said once", toasts.call() == ["caster asked to be your friend. Open Friends to answer."],
		toasts.call())
	hud._apply_broadcast(asks.call(1, "caster", 1000, 1, "Day One", 1005))
	check("an invitation lights Guild and is said", guild_button.text == "Guild •"
		and toasts.call().size() == 2 and toasts.call()[1] == "Day One invited you to join. Open Guild to answer.",
		[guild_button.text, toasts.call()])
	check("  and the same request is not said again", toasts.call().size() == 2, toasts.call())
	hud._apply_broadcast(asks.call(2, "medic", 1010, 1, "Day One", 1005))
	check("a second request is said, with the count",
		toasts.call()[-1] == "medic and 1 more asked to be your friend. Open Friends to answer."
		and friends_button.tooltip_text == "2 are waiting on your answer", [toasts.call()[-1], friends_button.tooltip_text])
	hud.free()

	# THROUGH A DOOR the new HUD lights its buttons from the last answer and
	# says nothing again.
	var next_area: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	next_area._build_message_box()
	next_area._paint_ask_buttons()
	next_area._apply_broadcast(asks.call(2, "medic", 1010, 1, "Day One", 1005))
	check("the next area's HUD keeps both lit and says nothing again",
		(next_area.get_node("%friendsbutton") as Button).text == "Friends •"
		and (next_area.get_node("%guildbutton") as Button).text == "Guild •"
		and next_area.message_rows.get_child_count() == 0, next_area.message_rows.get_child_count())
	check("  and a new area's HUD lights them before its first poll",
		_func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(").contains("_paint_ask_buttons()"))
	next_area._apply_broadcast(asks.call(0, "", 0, 0, "", 0))
	var after_guild: Button = next_area.get_node("%guildbutton") as Button
	check("answered, both go out, and Guild gets its own hint back",
		(next_area.get_node("%friendsbutton") as Button).text == "Friends"
		and after_guild.text == "Guild" and after_guild.tooltip_text == guild_tip, [after_guild.text, after_guild.tooltip_text])
	next_area.free()

	# ANOTHER ACCOUNT ON THIS MACHINE starts from nothing.
	hud_script._asks_said_by = "someoneelse"
	hud_script._asks_said = {"friends": 999999, "guild": 999999}
	var other: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	other._build_message_box()
	other._apply_broadcast(asks.call(1, "caster", 1000, 0, "", 0))
	check("a different account's waiting request is said to it",
		other.message_rows.get_child_count() == 1, other.message_rows.get_child_count())
	other.free()
	hud_script._forget_asks()
	print("  friend requests and guild invitations reach the player they wait on")


func _test_the_login_screen_asks_without_a_login() -> void:
	section("LOGIN - the screen asks if the server is there without a login")

	# Found in the browser build on day 1: the login screen's five-second probe
	# asked /api/auth/session, which answers 401 to nobody signed in, so the
	# console filled with a red "Failed to load resource" line every five
	# seconds and the server logged a 401 for every idle player.
	var probe := _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _on_reconnect_poll_timeout(")
	check("the login screen's probe asks /api/status",
		probe.contains("Api.get_json(\"/api/status\"") and not probe.contains("Api.get_json(\"/api/auth/session\""),
		probe.length())
	# AND OPENING THE GAME WITH NOTHING REMEMBERED asks nothing that needs a login:
	# the /api/status answer it already has says whether the server is there.
	var opening := _func_body(_code_src("res://src/systems/api.gd"), "func probe_and_resume(")
	var nothing_remembered: String = opening.substr(opening.find("\telse:"), 80)
	check("  and so does opening the game with no login remembered",
		opening.contains("var status_res: Dictionary = await refresh_build_info()")
		and nothing_remembered.contains("res = status_res") and not nothing_remembered.contains("auth/session"),
		nothing_remembered)


func _test_a_gateway_saying_no_answer_is_no_answer() -> void:
	section("API - a gateway's 502 or 504 is the server not answering")

	# Found in the browser build on day 1: behind the site's proxy, app.py down
	# answers 502 from the proxy, and the login screen said "Connected to the
	# Elusion server." Each answer below is handed to Api._read_answer() as an
	# HTTPRequest would hand it over, with no network.
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	var seen: Dictionary = {}
	for status in [502, 504, 503, 500, 401, 200]:
		Api.server_online = status == 502 or status == 504
		var http := HTTPRequest.new()
		add_child(http)
		var got: Array = []
		var reading := func() -> void:
			got.append(await Api._read_answer(http, "", "/api/status"))
		reading.call()
		http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, status, PackedStringArray(),
			"{}".to_utf8_buffer())
		var res: Dictionary = got[0] if not got.is_empty() else {}
		seen[status] = [int(res.get("status", -1)), Api.server_online]
	check("a 502 from the proxy reads as no answer, and offline", seen.get(502) == [0, false], seen.get(502))
	check("  so does a 504", seen.get(504) == [0, false], seen.get(504))
	check("  but the server's own 503, 500 and 401 are answers",
		seen.get(503) == [503, true] and seen.get(500) == [500, true] and seen.get(401) == [401, true],
		[seen.get(503), seen.get(500), seen.get(401)])
	check("  and a 200 is a 200", seen.get(200) == [200, true], seen.get(200))
	Api.server_online = kept_online
	Api.reachability_known = kept_known


func _test_a_lost_server_is_asked_for_more_often() -> void:
	section("CONNECTION - a lost server is asked for more often until it answers")

	# Day 1: a 16-second server restart showed "Connection lost" for 12 seconds
	# after the server was back, because the next poll was up to ten seconds
	# away. While the strip is up the poll runs every OFFLINE_POLL_SECONDS.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_status_strip()
	hud._build_message_box()
	var timer := Timer.new()
	timer.name = "BroadcastPoll"
	timer.wait_time = hud.BROADCAST_POLL_SECONDS
	hud.add_child(timer)
	var kept_token: String = Api.token
	Api.token = "test-not-a-real-token"
	hud._last_contact_msec = Time.get_ticks_msec() - int((hud.OFFLINE_GRACE_SECONDS + 5.0) * 1000.0)
	hud._tick_connection_status()
	check("past the grace, the strip is up and the poll asks every %.0f s" % hud.OFFLINE_POLL_SECONDS,
		hud.status_strip.visible and is_equal_approx(timer.wait_time, hud.OFFLINE_POLL_SECONDS),
		[hud.status_strip.visible, timer.wait_time])
	check("  which is quicker than the usual pace", hud.OFFLINE_POLL_SECONDS < hud.BROADCAST_POLL_SECONDS)
	hud._note_server_contact()
	check("the first answer puts the usual pace back and takes the strip down",
		is_equal_approx(timer.wait_time, hud.BROADCAST_POLL_SECONDS) and not hud.status_strip.visible,
		[timer.wait_time, hud.status_strip.visible])
	Api.token = kept_token
	hud.free()


func _test_the_bag_is_the_servers() -> void:
	section("THE BAG IS THE SERVER'S - a drag or the bin is a request, the grid drawn from the answer")

	# A save carried the whole bag, and the server trimmed it to what it had
	# granted (E-1): a gain was caught, and the arrangement and every loss were
	# this client's word. Now each change is one request (ONE CELL AT A TIME in
	# app.py, test_bagmoves.py), and a save carries no bag and no bank.
	var ss_code: String = _code_src("res://src/systems/serverstorage.gd")
	check("a save no longer sends the bag or the bank",
		not ss_code.contains("\"/api/character/inventory\"") and not ss_code.contains("\"/api/account/bank\""))
	check("  and the based_on bookkeeping went with it",
		not _code_src("res://src/systems/characterdata.gd").contains("func note_server_bag(")
		and not ss_code.contains("bag_base"))

	var kept_slots: Array = CharacterData.character_slots.duplicate(true)
	var kept_index: int = CharacterData.active_character_index
	CharacterData.character_slots = [{"character": "warrior", "inventory": [], "gold": 10},
		{"character": "mage", "inventory": [], "gold": 10}, null, null]
	CharacterData.active_character_index = 0

	# OUR OWN TWO ITEMS, so this runs without the art pack (the hotbar test's
	# way): a potion that stacks to 20 and a sword that does not stack.
	var potion := ItemData.new()
	potion.item_id = "zz_bag_test_potion"
	potion.display_name = "Bag Test Potion"
	potion.stackable = true
	potion.max_stack = 20
	var sword := ItemData.new()
	sword.item_id = "zz_bag_test_sword"
	sword.display_name = "Bag Test Sword"
	ItemRegistry._items[potion.item_id] = potion
	ItemRegistry._items[sword.item_id] = sword

	# A FAKE SERVER: every request is written down and answered, a frame
	# later, with whatever is next in `answers`.
	var sent: Array = []
	var answers: Array = []
	var fake := func(path: String, body: Dictionary) -> Dictionary:
		sent.append([path, body])
		await get_tree().process_frame
		return answers.pop_front() if not answers.is_empty() else {"ok": false, "status": 0, "error": "no answer"}
	var settle := func(grid: InventoryContainer) -> void:
		var frames := 0
		while grid.is_busy() and frames < 30:
			await get_tree().process_frame
			frames += 1
		await get_tree().process_frame

	var carry := InventoryContainer.new()
	carry.is_carry = true
	add_child(carry)
	carry.send_override = fake
	carry.load_save_array([{"item_id": "zz_bag_test_potion", "quantity": 5}, {"item_id": "zz_bag_test_sword", "quantity": 1}])

	# ---- a drag is drawn at once and sent as one move -------------------------
	var held_after: Array = [null, {"item_id": "zz_bag_test_sword", "quantity": 1}, null, null, null, null, null,
		{"item_id": "zz_bag_test_potion", "quantity": 5}]
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": held_after}})
	carry.get_slot_at(7)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(0)))
	check("a drag onto an empty cell is drawn at once",
		_hb_holds(carry.get_slot_at(7), "zz_bag_test_potion", 5) and carry.get_slot_at(0).is_empty())
	check("  and sent as one move, naming what was dragged",
		sent.size() == 1 and sent[0][0] == InventoryContainer.CARRY_MOVE_PATH
		and sent[0][1] == {"slot": 0, "from": 0, "to": 7, "item_id": "zz_bag_test_potion"}, sent)
	await settle.call(carry)
	check("  the answer agrees, and the grid is the server's",
		_hb_holds(carry.get_slot_at(7), "zz_bag_test_potion", 5) and _hb_holds(carry.get_slot_at(1), "zz_bag_test_sword", 1))

	# ---- two quick drags: in order, one at a time, only the last answer drawn -
	sent.clear()
	var first_answer: Array = [{"item_id": "zz_bag_test_sword", "quantity": 1}]
	var last_answer: Array = [{"item_id": "zz_bag_test_sword", "quantity": 1}, null, null,
		{"item_id": "zz_bag_test_potion", "quantity": 5}]
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": first_answer}})
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": last_answer}})
	carry.get_slot_at(0)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(1)))
	carry.get_slot_at(3)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(7)))
	check("two quick drags: the second waits for the first's answer", sent.size() == 1, sent.size())
	await settle.call(carry)
	check("  then goes, in the order made", sent.size() == 2
		and int(sent[0][1]["from"]) == 1 and int(sent[1][1]["from"]) == 7, sent)
	check("  and only the last answer is drawn - the first would flick the second drag back",
		_hb_holds(carry.get_slot_at(0), "zz_bag_test_sword", 1) and _hb_holds(carry.get_slot_at(3), "zz_bag_test_potion", 5),
		carry.to_save_array().slice(0, 4))

	# ---- a grid that was out of date is put right by the 409 ------------------
	# The resync names character 1, not the one being played, so no player the
	# suite may have left in the tree has its purse or its grid touched; the
	# real server names the requesting slot, and the HUD's grid is this one.
	sent.clear()
	var truth: Array = [{"item_id": "zz_bag_test_sword", "quantity": 1}, null, {"item_id": "zz_bag_test_potion", "quantity": 2}]
	answers.append({"ok": false, "status": 409, "error": "Your backpack changed on the server.",
		"data": {"resync": {"slot": 1, "gold": 10, "inventory": truth, "trade": null, "reason": "stale_save"}}})
	carry.get_slot_at(9)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(3)))
	await settle.call(carry)
	check("a move the server refused as stale redraws the grid it holds",
		_hb_holds(carry.get_slot_at(2), "zz_bag_test_potion", 2) and carry.get_slot_at(9).is_empty()
		and carry.get_slot_at(3).is_empty(), carry.to_save_array().slice(0, 10))
	check("  and the character's copy follows it, through apply_server_carry()",
		(CharacterData.character_slots[1].get("inventory", []) as Array).size() >= 3
		and CharacterData.character_slots[1]["inventory"][2] is Dictionary)
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	hud._on_carry_adopted({"reason": "stale_save", "inventory": [], "trade": null})
	check("  and puts up no message - the grid simply shows the truth", hud._unlogged_lines.is_empty(),
		hud._unlogged_lines)
	hud._on_carry_adopted({"inventory": [], "trade": null})
	check("  a resync for anything else, a trade, still does", hud._unlogged_lines.size() == 1,
		hud._unlogged_lines)
	hud.free()

	# ---- the bin ----------------------------------------------------------------
	sent.clear()
	answers.append({"ok": true, "status": 200, "data": {"slot": 0, "inventory": [{"item_id": "zz_bag_test_sword", "quantity": 1}]}})
	carry.request_discard(2, "zz_bag_test_sword")
	check("a bin that names the wrong item destroys nothing and sends nothing",
		_hb_holds(carry.get_slot_at(2), "zz_bag_test_potion", 2) and sent.is_empty())
	carry.request_discard(2, "zz_bag_test_potion")
	check("the bin takes the stack off at once",
		carry.get_slot_at(2).is_empty())
	check("  and asks the server to destroy it",
		sent.size() == 1 and sent[0][0] == InventoryContainer.CARRY_DISCARD_PATH
		and sent[0][1] == {"slot": 0, "position": 2, "item_id": "zz_bag_test_potion"}, sent)
	await settle.call(carry)

	# ---- no answer at all leaves the drawing alone, and says so --------------
	sent.clear()
	carry.get_slot_at(5)._drop_data(Vector2.ZERO, _hb_drag(carry.get_slot_at(0)))
	await settle.call(carry)
	check("a move with no answer keeps what is drawn - the next answer puts it right",
		sent.size() == 1 and _hb_holds(carry.get_slot_at(5), "zz_bag_test_sword", 1))

	# ---- the bank's grid uses the bank's routes; a grid that is neither, none --
	var bank := InventoryContainer.new()
	bank.grid_width = 10
	bank.grid_height = 5
	bank.is_bank = true
	add_child(bank)
	bank.set_slot_type(InventorySlot.BANK_SLOT_TYPE)
	bank.send_override = fake
	bank.load_save_array([{"item_id": "zz_bag_test_sword", "quantity": 1}])
	sent.clear()
	var bank_truth: Array = [null, null, null, {"item_id": "zz_bag_test_sword", "quantity": 1}]
	answers.append({"ok": false, "status": 409, "error": "The bank changed on the server.",
		"data": {"account": {"bank_inventory": bank_truth}}})
	bank.get_slot_at(20)._drop_data(Vector2.ZERO, _hb_drag(bank.get_slot_at(0)))
	check("a drag inside the bank is a bank move, with no character slot",
		sent.size() == 1 and sent[0][0] == InventoryContainer.BANK_MOVE_PATH
		and sent[0][1] == {"from": 0, "to": 20, "item_id": "zz_bag_test_sword"}, sent)
	await settle.call(bank)
	check("  and a stale one redraws the bank the server holds",
		_hb_holds(bank.get_slot_at(3), "zz_bag_test_sword", 1) and bank.get_slot_at(20).is_empty())
	sent.clear()
	bank.request_discard(3, "zz_bag_test_sword")
	check("the bank's bin is the bank's discard",
		sent.size() == 1 and sent[0][0] == InventoryContainer.BANK_DISCARD_PATH
		and sent[0][1] == {"position": 3, "item_id": "zz_bag_test_sword"}, sent)
	await settle.call(bank)

	var loose := InventoryContainer.new()
	add_child(loose)
	loose.send_override = fake
	loose.load_save_array([{"item_id": "zz_bag_test_sword", "quantity": 1}])
	sent.clear()
	loose.get_slot_at(4)._drop_data(Vector2.ZERO, _hb_drag(loose.get_slot_at(0)))
	check("a grid that is neither the bag nor the bank sends nothing", sent.is_empty())

	# ---- the wiring, read from the code -------------------------------------
	check("the inventory screen marks its grid as the carry",
		_func_body(_code_src("res://src/ui/inventory/inventoryscreen.gd"), "func _wire_inventory_container(")
			.contains("_container.is_carry = true"))
	check("the bank marks its grid as the bank",
		_code_src("res://src/ui/bank/bankinventory.gd").contains("bank_container.is_bank = true"))
	check("the bin asks the grid to discard, naming the item the dialog showed",
		_func_body(_code_src("res://src/ui/inventory/trashslot.gd"), "func _on_delete_confirmed(")
			.contains("request_discard(_pending_source_slot.slot_index, named)"))
	var screen_src: String = _code_src("res://src/ui/inventory/inventoryscreen.gd")
	check("a pile of coins is cashed by the server, not added to the purse here",
		_func_body(screen_src, "func _cash_pile(").contains("/api/character/inventory/cash")
		and not screen_src.contains("player.add_gold(") and not screen_src.contains("player.add_lusions("))
	check("a potion's answer is drawn as the bag",
		_func_body(screen_src, "func _use_consumable(").contains("_adopt_carry("))

	carry.queue_free()
	bank.queue_free()
	loose.queue_free()
	ItemRegistry._items.erase(potion.item_id)
	ItemRegistry._items.erase(sword.item_id)
	CharacterData.character_slots = kept_slots
	CharacterData.active_character_index = kept_index
	print("  the bag: drags and the bin are requests, in order, drawn from the last answer")


func _test_the_map_comes_back() -> void:
	section("MAP - what you uncovered comes back at the next login")

	# Day 1: a walk of the field, a logout, and the map was blank again. Two
	# faults. The load built each character from /api/character, which carries
	# no map (the listing, /api/save, does), so every login started with none;
	# and the map rides a save only when WorldMap's revision moves, at most
	# every SAVE_REVISION_SECONDS, so a logout inside that window left the walk
	# behind. The first save after the next walk then wrote the few new tiles
	# over everything before.
	var storage_script: GDScript = load("res://src/systems/serverstorage.gd") as GDScript
	var map: Dictionary = {"field": {"w": 2, "h": 2, "ox": 0, "oy": 0, "bits": "x"}}
	var merged: Dictionary = storage_script.with_listing({"class_id": "warrior"}, {"slot": 0, "explored": map})
	check("a character from /api/character takes the map from the listing", merged.get("explored") == map,
		merged.get("explored"))
	var own: Dictionary = {"class_id": "warrior", "explored": {"elusion": {}}}
	check("  and one that already has a map keeps its own",
		storage_script.with_listing(own, {"explored": map}).get("explored") == {"elusion": {}})
	check("  the load builds every character that way",
		_func_body(_code_src("res://src/systems/serverstorage.gd"), "func load(")
			.contains("_slot_from_server(with_listing("))

	var kept_rev: int = WorldMap._revision
	var kept_pending: bool = WorldMap._revision_pending
	WorldMap._revision_pending = true
	WorldMap._revision_at_ms = Time.get_ticks_msec()
	var before: int = WorldMap.save_revision()
	check("a walk inside the window has not moved the revision yet", before == kept_rev, [before, kept_rev])
	check("flush_pending() counts it now", WorldMap.flush_pending() and WorldMap.save_revision() == before + 1)
	check("  and only once", not WorldMap.flush_pending())
	# LEAVING, through the real finish_saving(), with no time to wait: the walk
	# is counted and the character's save carries the map at the new revision.
	var kept_slots: Array = CharacterData.character_slots.duplicate(true)
	var kept_index: int = CharacterData.active_character_index
	CharacterData.character_slots = [{"character": "warrior"}, null, null, null]
	CharacterData.active_character_index = 0
	WorldMap._revision_pending = true
	var walked_at: int = WorldMap.save_revision()
	await CharacterData.finish_saving(0.0)
	check("leaving counts the walk and puts it in the save",
		int(CharacterData.character_slots[0].get("explored_rev", -1)) == walked_at + 1
		and CharacterData.character_slots[0].has("explored"), CharacterData.character_slots[0])
	CharacterData.character_slots = kept_slots
	CharacterData.active_character_index = kept_index
	WorldMap._revision = kept_rev
	WorldMap._revision_pending = kept_pending


func _test_enemies_keep_their_place_in_the_ring() -> void:
	section("FORMATION - a chasing enemy keeps its place on the ring")

	# Day 1, measured while timing the field: within a second 37 of the 40 ring
	# slots were owned by enemies not standing on them and none of 12 chasers
	# held one. Each 0.4 s review that found nothing better forgot the slot it
	# had without releasing it, so every enemy ran at the player's own position.
	var kept_owners: Dictionary = BaseEnemy._slot_owners.duplicate()
	BaseEnemy._slot_owners.clear()
	var holder := Node2D.new()
	add_child(holder)
	var anchor := CharacterBody2D.new()
	holder.add_child(anchor)
	anchor.global_position = Vector2(9000, 9000)
	var pack: PackedScene = load("res://scene/enemy/darkbushmage.tscn") as PackedScene
	var pack_of: Array = []
	for i in 6:
		var e: Node = pack.instantiate()
		holder.add_child(e)
		e.set_physics_process(false)
		e.set_process(false)
		e.global_position = anchor.global_position + Vector2.RIGHT.rotated(TAU * i / 6.0) * 150.0
		e.player = anchor
		pack_of.append(e)
	var holding := func() -> Array:
		var out: Array = []
		for e in pack_of:
			if e._claimed_slot != -1 and BaseEnemy._slot_owners.get(e._claimed_slot) == e:
				out.append(e._claimed_slot)
		return out
	var leaked := func() -> int:
		var n := 0
		for slot in BaseEnemy._slot_owners:
			var who = BaseEnemy._slot_owners[slot]
			if is_instance_valid(who) and who._claimed_slot != slot:
				n += 1
		return n
	for e in pack_of:
		e._ensure_slot_claimed()
	var first: Array = holding.call()
	check("six chasers each claim a slot of their own", first.size() == 6, first)
	# Five reviews each, the way 0.4 s ticks would bring them.
	for round_i in 5:
		for e in pack_of:
			e._slot_review_time = 0.0
			e._ensure_slot_claimed()
	var after: Array = holding.call()
	check("  and still hold one after five reviews", after.size() == 6, after)
	check("  no slot is owned by an enemy not standing on it", leaked.call() == 0, leaked.call())
	check("  six slots owned, not more", BaseEnemy._slot_owners.size() == 6, BaseEnemy._slot_owners.size())
	var leaver: Node = pack_of[0]
	var its_slot: int = leaver._claimed_slot
	leaver._release_slot()
	check("one that gives up its slot frees it for the others",
		not BaseEnemy._slot_owners.has(its_slot) and BaseEnemy._slot_owners.size() == 5, BaseEnemy._slot_owners.keys())
	holder.queue_free()
	BaseEnemy._slot_owners.clear()
	BaseEnemy._slot_owners.merge(kept_owners)
	print("  formation: %d chasers, %d held after the reviews" % [pack_of.size(), after.size()])


func _test_a_door_is_quick() -> void:
	section("DOORS - the fade is short, and the area is built under it")

	# 0.6 s of every 0.65 s door was the fade. Halved each way on day 1.
	check("a door fades for 0.15 s each way", is_equal_approx(SceneTransition.fade_duration, 0.15),
		SceneTransition.fade_duration)
	var body := _func_body(_code_src("res://src/systems/scenetransition.gd"), "func change_scene(")
	var out_at := body.find("await _fade_out()")
	var swap_at := body.find("change_scene_to_packed(")
	var in_at := body.find("await _fade_in()")
	check("  the new area is built while the screen is black",
		out_at != -1 and swap_at > out_at and in_at > swap_at, [out_at, swap_at, in_at])


const EMOJI_FONT := "res://assets/fonts/NotoColorEmoji.ttf"
const EMOJI_FONT_MAX_BYTES := 6_000_000


func _emoji_strike_ppem(bytes: PackedByteArray) -> int:
	# The ppem of the font's first CBLC strike, read from the table directory:
	# 12-byte header, then 16-byte records of tag, checksum, offset, length.
	# A BitmapSize record follows CBLC's 8-byte header; ppemX is its byte 44.
	if bytes.size() < 12:
		return -1
	var tables: int = (bytes[4] << 8) | bytes[5]
	for i in tables:
		var at: int = 12 + i * 16
		if bytes.slice(at, at + 4).get_string_from_ascii() == "CBLC":
			var offset: int = (bytes[at + 8] << 24) | (bytes[at + 9] << 16) | (bytes[at + 10] << 8) | bytes[at + 11]
			return bytes[offset + 8 + 44] if offset + 52 < bytes.size() else -1
	return -1


func _test_the_emoji_font_is_chat_sized() -> void:
	section("EMOJI - the colour font is drawn at chat size, so it ships at chat size")

	# Google's Noto Color Emoji is 10.8 MB of 136x128 pictures, and it was three
	# quarters of the browser's game file. Chat draws emoji at 10-16 px, so the
	# shipped copy is scaled to 32 ppem by tools/shrink_emoji_font.py: every
	# emoji kept, 4.6 MB. Dropping Google's file back in adds 6 MB to every
	# browser player's download, on the first visit and after every update.
	var bytes := FileAccess.get_file_as_bytes(EMOJI_FONT)
	check("the emoji font is the chat-size build, under %.0f MB" % (EMOJI_FONT_MAX_BYTES / 1_000_000.0),
		bytes.size() > 0 and bytes.size() < EMOJI_FONT_MAX_BYTES, bytes.size())
	var ppem := _emoji_strike_ppem(bytes)
	check("  its pictures are one strike of 32 ppem", ppem == 32, ppem)
	var font := load(EMOJI_FONT) as FontFile
	var missing: Array = []
	for code in [0x1F600, 0x1F44D, 0x1F525, 0x1F41F, 0x2694, 0x1F6E1, 0x1F4B0, 0x1F389, 0x2764, 0x1F602, 0x1F62D, 0x1F64F]:
		if font == null or not font.has_char(code):
			missing.append("%X" % code)
	check("  and still has every emoji: the common ones are there", missing.is_empty(), missing)
	var supported: int = font.get_supported_chars().length() if font != null else 0
	# 1,493 is what Godot reports for Google's own file too (its cmap lists 1,494).
	check("  as many characters as Google's release", supported >= 1493, supported)


# A small HTTP/1.1 server inside the suite, so the connection pool can be
# watched against every way a real server or proxy behaves, with no network.
# mode: "keep" answers and keeps the connection; "close" answers with
# Connection: close and closes half a second later, as Flask's own server
# does, reading nothing more from it; "drop" answers and closes without saying so;
# "eat_next" reads the next request, closes, and goes back to "keep".
# /slow is answered two seconds late; /gz is answered gzip-compressed when asked
# for.
class FakeHttpServer extends Node:
	var server := TCPServer.new()
	var port := 0
	var accepted := 0
	var seen: Array[String] = []
	var mode := "keep"
	var _peers: Array = []
	var _late: Array = []

	func open_connections() -> int:
		var n := 0
		for c in _peers:
			(c.peer as StreamPeerTCP).poll()
			if (c.peer as StreamPeerTCP).get_status() == StreamPeerTCP.STATUS_CONNECTED:
				n += 1
		return n

	func shutdown() -> void:
		server.stop()
		for c in _peers:
			(c.peer as StreamPeerTCP).disconnect_from_host()
		_peers.clear()

	func start() -> bool:
		for p in range(47100, 47200):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return true
		return false

	func _process(_delta: float) -> void:
		for c in _peers.duplicate():
			if c.get("closing_at", 0) > 0 and Time.get_ticks_msec() >= c.closing_at:
				(c.peer as StreamPeerTCP).disconnect_from_host()
				_peers.erase(c)
		for late in _late.duplicate():
			if Time.get_ticks_msec() >= late.at:
				_late.erase(late)
				var peer_late: StreamPeerTCP = late.peer
				if peer_late.get_status() == StreamPeerTCP.STATUS_CONNECTED:
					peer_late.put_data(late.out)
		while server.is_connection_available():
			_peers.append({"peer": server.take_connection(), "buf": PackedByteArray()})
			accepted += 1
		for c in _peers.duplicate():
			var peer: StreamPeerTCP = c.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peers.erase(c)
				continue
			var waiting := peer.get_available_bytes()
			if waiting > 0:
				c.buf.append_array(peer.get_data(waiting)[1])
			if c.get("closing_at", 0) > 0:
				# Said it would close: whatever else arrives is never read.
				c.buf = PackedByteArray()
				continue
			var text: String = c.buf.get_string_from_ascii()
			var end := text.find("\r\n\r\n")
			if end == -1:
				continue
			var head := text.substr(0, end)
			var length := 0
			for h in head.split("\r\n"):
				if h.to_lower().begins_with("content-length:"):
					length = int(h.get_slice(":", 1).strip_edges())
			if c.buf.size() < end + 4 + length:
				continue
			c.buf = c.buf.slice(end + 4 + length)
			var first := head.get_slice("\r\n", 0)
			seen.append(first.get_slice(" ", 0) + " " + first.get_slice(" ", 1))
			_answer(c, peer, first.get_slice(" ", 1), head)

	func _answer(c: Dictionary, peer: StreamPeerTCP, path: String, head: String) -> void:
		if mode == "eat_next":
			mode = "keep"
			peer.disconnect_from_host()
			_peers.erase(c)
			return
		var body := JSON.stringify({"path": path, "n": seen.size()}).to_utf8_buffer()
		var extra := ""
		if path == "/gz" and head.to_lower().contains("accept-encoding: gzip"):
			body = body.compress(FileAccess.COMPRESSION_GZIP)
			extra = "Content-Encoding: gzip\r\n"
		if mode == "close":
			extra += "Connection: close\r\n"
		var out := ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n%s\r\n"
			% [body.size(), extra]).to_ascii_buffer()
		out.append_array(body)
		if path == "/slow":
			_late.append({"peer": peer, "out": out, "at": Time.get_ticks_msec() + 2000})
			return
		peer.put_data(out)
		if mode == "close":
			c["closing_at"] = Time.get_ticks_msec() + 500
		elif mode == "drop":
			peer.disconnect_from_host()
			_peers.erase(c)


func _test_connections_are_kept_open() -> void:
	section("NETWORK - the desktop game keeps its connections to the server open")

	# Day 1, measured at a 50 ms ping and 60 fps: a request on a new connection
	# took 133 ms, one on a connection kept open 67 ms; the login's four requests
	# went from 0.7 s to 0.4 s. Over HTTPS a new connection costs one more round
	# trip again. See connectionpool.gd for the rules checked here.
	var pool = Api._pool
	check("the desktop game sends its JSON through kept-open connections", pool != null)
	if pool == null:
		return
	var fake := FakeHttpServer.new()
	add_child(fake)
	if not fake.start():
		check("a free local port for the suite's own server", false)
		fake.queue_free()
		return
	var kept_url: String = ApiForTests.BASE_URL
	var kept_online: bool = Api.server_online
	var kept_known: bool = Api.reachability_known
	var kept_token: String = Api.token
	Api.token = ""
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % fake.port
	var opened: int = pool.connections_opened

	var oks := 0
	var seen_at := 0
	for i in 5:
		var one: Dictionary = await Api.get_json("/one")
		if one.get("ok", false) and one.data is Dictionary and one.data.get("path") == "/one":
			oks += 1
	check("five requests in a row are answered", oks == 5, oks)
	check("  over one connection", fake.accepted == 1 and pool.connections_opened - opened == 1,
		[fake.accepted, pool.connections_opened - opened])

	var together: Array = []
	for i in 3:
		(func() -> void: together.append(await Api.get_json("/together"))).call()
	var waited := 0.0
	while together.size() < 3 and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var all_ok := together.size() == 3
	for r in together:
		all_ok = all_ok and r.get("ok", false)
	check("three at once are all answered, each on its own connection",
		all_ok and fake.accepted == 3, [together.size(), fake.accepted])

	var gz: Dictionary = await Api.get_json("/gz")
	check("a compressed answer is unpacked", gz.get("ok", false) and gz.data is Dictionary
		and gz.data.get("path") == "/gz", gz)

	# Up to three connections are open now, so six requests to a server that
	# closes after each answer need at least three new ones - and no timeouts.
	fake.mode = "close"
	var before: int = fake.accepted
	var closing_from := Time.get_ticks_msec()
	oks = 0
	for i in 6:
		if (await Api.get_json("/closing")).get("ok", false):
			oks += 1
	seen_at = fake.seen.size()
	var closing_post: Dictionary = await Api.post("/closing", {"n": 1})
	check("a server that says it will close gets every request, without waiting for it (Flask's own does this)",
		oks == 6 and closing_post.get("ok", false) and fake.accepted - before >= 3
		and Time.get_ticks_msec() - closing_from < 2000,
		[oks, closing_post.get("status"), fake.accepted - before, Time.get_ticks_msec() - closing_from])

	fake.mode = "keep"
	await Api.get_json("/warm")
	fake.mode = "eat_next"
	seen_at = fake.seen.size()
	var again: Dictionary = await Api.get_json("/again")
	check("a GET lost on a reused connection is asked again once, and answered",
		again.get("ok", false) and fake.seen.slice(seen_at) == ["GET /again", "GET /again"],
		[again.get("status"), fake.seen.slice(seen_at)])

	await Api.get_json("/warm")
	fake.mode = "eat_next"
	seen_at = fake.seen.size()
	var buy: Dictionary = await Api.post("/buy", {"item_id": "ironsword"})
	check("a POST lost the same way is never sent twice: it fails as no answer",
		not buy.get("ok", true) and int(buy.get("status", -1)) == 0
		and fake.seen.slice(seen_at) == ["POST /buy"], [buy.get("status"), fake.seen.slice(seen_at)])

	fake.mode = "drop"
	await Api.get_json("/warm")
	fake.mode = "keep"
	await get_tree().create_timer(0.2).timeout
	seen_at = fake.seen.size()
	var after_drop: Dictionary = await Api.get_json("/after_drop")
	check("a connection the server dropped while idle is not used: the next request goes once and is answered",
		after_drop.get("ok", false) and fake.seen.slice(seen_at) == ["GET /after_drop"],
		[after_drop.get("status"), fake.seen.slice(seen_at)])
	# A POST is never asked twice, so this one only works if the dropped
	# connection is noticed before anything is sent on it.
	fake.mode = "drop"
	await Api.get_json("/warm")
	fake.mode = "keep"
	await get_tree().create_timer(0.2).timeout
	seen_at = fake.seen.size()
	var post_after_drop: Dictionary = await Api.post("/after_drop", {"n": 1})
	check("  and so is a POST: it is checked before it is sent on it",
		post_after_drop.get("ok", false) and fake.seen.slice(seen_at) == ["POST /after_drop"],
		[post_after_drop.get("status"), fake.seen.slice(seen_at)])

	pool.idle_close_seconds = 0.3
	await Api.get_json("/idle")
	var open_before: int = fake.open_connections()
	await get_tree().create_timer(0.6).timeout
	check("a connection left idle is closed by the game, before a server or proxy would",
		open_before >= 1 and fake.open_connections() == 0, [open_before, fake.open_connections()])
	pool.idle_close_seconds = pool.IDLE_CLOSE_SECONDS

	var started := Time.get_ticks_msec()
	var slow: Dictionary = await Api.get_json("/slow", 0.4)
	var took := Time.get_ticks_msec() - started
	check("a server that never answers times out on time", not slow.get("ok", true)
		and int(slow.get("status", -1)) == 0 and took < 1500, [slow.get("status"), took])
	var next_one: Dictionary = await Api.get_json("/after_slow")
	check("  and the request after it is answered, not handed the late reply",
		next_one.get("ok", false) and next_one.data is Dictionary and next_one.data.get("path") == "/after_slow",
		next_one.get("data"))

	fake.shutdown()
	await get_tree().create_timer(0.1).timeout
	var nothing: Dictionary = await Api.get_json("/nobody", 2.0)
	check("nothing listening is no answer, at once", int(nothing.get("status", -1)) == 0, nothing.get("status"))

	check("an address the pool cannot use is refused, not guessed at",
		PoolForTests.parse_base_url("example.com").is_empty() and PoolForTests.parse_base_url("ftp://x").is_empty())
	check("  and one it can is read in full",
		PoolForTests.parse_base_url("https://api.elusionrpg.com") == {"tls": true, "host": "api.elusionrpg.com", "port": 443, "prefix": ""}
		and PoolForTests.parse_base_url("http://127.0.0.1:5000/") == {"tls": false, "host": "127.0.0.1", "port": 5000, "prefix": ""}
		and PoolForTests.parse_base_url("https://example.com:8443/game") == {"tls": true, "host": "example.com", "port": 8443, "prefix": "/game"})

	ApiForTests.BASE_URL = kept_url
	Api.token = kept_token
	Api.server_online = kept_online
	Api.reachability_known = kept_known
	fake.queue_free()
	print("  network: %d connections opened by the pool for %d requests" % [pool.connections_opened - opened, fake.seen.size()])


func _test_the_powers_panel_closes() -> void:
	section("POWERS - the owner's ranks window has a × like every other")

	# Asked for on day 1: the only way out of it was the button that opened it.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var kept_owner: bool = Api.is_owner
	Api.is_owner = true
	hud._toggle_powers_panel()
	var panel: Control = hud.get_node_or_null("powerspanel")
	var x: Button = panel.find_child("powersclosebutton", true, false) as Button if panel != null else null
	check("the Powers window opens with a × in its header",
		panel != null and panel.visible and x != null and x.text == "×" and x.focus_mode == Control.FOCUS_NONE,
		[panel != null, x.text if x != null else "no button"])
	if x != null:
		x.pressed.emit()
	check("  pressing it closes the window", panel != null and not panel.visible)
	hud._toggle_powers_panel()
	check("  and the Powers button opens it again", panel != null and panel.visible)
	check("  its list is still where the server's answer is written",
		hud.get_node_or_null(hud.POWERS_ROWS) is VBoxContainer)
	Api.is_owner = kept_owner
	hud.free()


func _test_the_staff_windows_share_one_look() -> void:
	section("STAFF WINDOWS - Owner, Staff and Powers wear one navy and gold theme")

	# Asked for on day 1: the three staff windows had three looks (navy, brown,
	# navy) and none had the inventory's gold boxes. They now share
	# staff_ui_theme.tres, so a colour changed there changes all three.
	const STAFF_THEME_PATH := "res://assets/themes/staff_ui_theme.tres"
	var theme: Theme = load(STAFF_THEME_PATH) as Theme
	check("the staff theme loads", theme != null)
	if theme == null:
		return
	var window: StyleBoxFlat = theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	var tab_on: StyleBoxFlat = theme.get_stylebox("tab_selected", "TabContainer") as StyleBoxFlat
	var tab_box: StyleBoxFlat = theme.get_stylebox("panel", "TabContainer") as StyleBoxFlat
	var is_navy := func(c: Color) -> bool: return c.b > c.r and c.b > c.g and c.v < 0.2
	var is_gold := func(c: Color) -> bool: return c.r > c.g and c.g > c.b and c.r > 0.45
	check("  its windows are navy with a gold frame",
		window != null and is_navy.call(window.bg_color) and is_gold.call(window.border_color)
		and window.border_width_left >= 2,
		str(window.bg_color) + " " + str(window.border_color) if window != null else "no window style")
	check("  its tabs and the page under them are boxed in gold",
		tab_on != null and tab_box != null and is_gold.call(tab_on.border_color)
		and is_gold.call(tab_box.border_color) and tab_box.border_width_top >= 1)
	check("  it has the header box and the inner box every window uses",
		theme.get_type_variation_base(&"PanelHeader") == &"PanelContainer"
		and theme.get_type_variation_base(&"PanelSub") == &"PanelContainer")
	var staff_menu: StyleBoxFlat = theme.get_stylebox("panel", "PopupMenu") as StyleBoxFlat
	check("  and its dropdown lists and menus are navy in a gold frame, not Godot's grey",
		theme.has_stylebox("panel", "PopupMenu") and staff_menu != null
		and is_navy.call(staff_menu.bg_color) and is_gold.call(staff_menu.border_color))

	# NO WINDOW MAY QUIETLY KEEP ITS OLD LOOK. A per-node style override beats
	# the theme, so one left behind keeps an old colour no matter what the theme
	# says. Only the red and green action buttons keep their own colours.
	const KEEP_OWN_COLOURS := ["banbutton", "unbanbutton", "maintenancebutton"]
	var leftovers := func(root: Node) -> Array:
		var found: Array = []
		var nodes: Array = [root]
		nodes.append_array(root.find_children("*", "", true, false))
		for node in nodes:
			if not (node is Button or node is LineEdit or node is TabContainer or node is PanelContainer):
				continue
			if str(node.name) in KEEP_OWN_COLOURS:
				continue
			for style in ["normal", "hover", "pressed", "focus", "panel",
					"tab_selected", "tab_unselected", "tab_hovered"]:
				if (node as Control).has_theme_stylebox_override(style):
					found.append("%s/%s" % [node.name, style])
		return found

	var owner_panel: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate()
	var owner_left: Array = leftovers.call(owner_panel)
	check("the Owner window wears the staff theme",
		owner_panel.theme != null and owner_panel.theme.resource_path == STAFF_THEME_PATH,
		owner_panel.theme.resource_path if owner_panel.theme != null else "no theme")
	check("  with no button, field, tab or box keeping its own old style", owner_left.is_empty(), owner_left)
	var owner_header: Control = owner_panel.find_child("headerpanel", true, false)
	check("  and its title sits in the gold header box",
		owner_header != null and owner_header.theme_type_variation == &"PanelHeader")
	owner_panel.free()

	var staff_panel: Control = (load("res://scene/ui/staff/staffpanel.tscn") as PackedScene).instantiate()
	var staff_main: Control = staff_panel.get_node_or_null("mainpanel")
	var staff_left: Array = leftovers.call(staff_panel)
	check("the Staff window wears the staff theme, not the brown one",
		staff_main != null and staff_main.theme != null and staff_main.theme.resource_path == STAFF_THEME_PATH,
		staff_main.theme.resource_path if staff_main != null and staff_main.theme != null else "no theme")
	check("  with no button, field, tab or box keeping its own old style", staff_left.is_empty(), staff_left)
	staff_panel.free()

	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var kept_owner: bool = Api.is_owner
	Api.is_owner = true
	hud._toggle_powers_panel()
	var powers: Control = hud.get_node_or_null("powerspanel")
	var powers_header: Control = powers.find_child("header", true, false) if powers != null else null
	check("the Powers window wears the staff theme",
		powers != null and powers.theme != null and powers.theme.resource_path == STAFF_THEME_PATH)
	check("  with its title in the gold header box and no style of its own",
		powers_header != null and powers_header.theme_type_variation == &"PanelHeader"
		and powers != null and leftovers.call(powers).is_empty(),
		leftovers.call(powers) if powers != null else "no window")
	Api.is_owner = kept_owner
	hud.free()


func _test_players_right_click_menu() -> void:
	section("PLAYERS - right-click a name to whisper, add as a friend or trade")

	# Asked for on day 1. Out of the tree, like the chat menu's test: _ready()
	# never runs, so nothing polls a server, and with no token nothing is sent.
	var was := [Api.username, Api.token]
	Api.username = "me_myself"
	Api.token = ""
	var panel: Control = (load("res://scene/ui/players/playerspanel.tscn") as PackedScene).instantiate()
	var stranger: Control = panel._row({"username": "rowdy", "name": "mage", "level": 3,
		"area": "field", "role": "player", "guild_tag": "ABC", "guild": "Abc"})
	var mine: Control = panel._row({"username": "Me_Myself", "name": "warrior", "level": 9,
		"area": "field", "role": "player", "guild_tag": ""})
	check("somebody else's row can be right-clicked, and says so",
		stranger.tooltip_text == panel.ROW_HINT and not stranger.gui_input.get_connections().is_empty(),
		stranger.tooltip_text)
	check("  your own row has no menu",
		mine.tooltip_text == "" and mine.gui_input.get_connections().is_empty())
	var stops: Array = []
	for node in stranger.find_children("*", "Control", true, false):
		if (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			stops.append(str(node.name))
	check("  nothing on the row, the guild tag included, keeps the click from the row",
		stops.is_empty(), stops)

	var heard: Array = []
	panel.whisper_asked.connect(func(who: String) -> void: heard.append("whisper " + who))
	panel.friend_asked.connect(func(who: String) -> void: heard.append("friend " + who))
	panel.trade_asked.connect(func(who: String) -> void: heard.append("trade " + who))

	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	stranger.gui_input.emit(left)
	check("a left click opens nothing", panel.row_menu == null)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	stranger.gui_input.emit(right)
	var menu: PopupMenu = panel.row_menu
	var items: Array = []
	var title: String = ""
	if menu != null:
		for i in menu.item_count:
			if menu.is_item_separator(i):
				title = menu.get_item_text(i)
			else:
				items.append(menu.get_item_text(i))
	check("a right click opens their menu: Whisper, Add friend, Trade",
		menu != null and title == "rowdy" and items == ["Whisper", "Add friend", "Trade"], [title, items])
	if menu != null:
		for id in [panel.MENU_WHISPER, panel.MENU_FRIEND, panel.MENU_TRADE]:
			menu.id_pressed.emit(id)
	check("  and each asks for that, for them",
		heard == ["whisper rowdy", "friend rowdy", "trade rowdy"], heard)
	panel._menu_who = ""
	panel.open_row_menu("ME_MYSELF")
	check("  there is no menu for yourself, however it is typed", panel._menu_who == "")
	# THE MENU WEARS THE GAME'S LOOK. A theme with no PopupMenu in it leaves
	# Godot's grey box, which is what the first version of this menu showed.
	var game_theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	var menu_box: StyleBoxFlat = game_theme.get_stylebox("panel", "PopupMenu") as StyleBoxFlat \
		if game_theme != null and game_theme.has_stylebox("panel", "PopupMenu") else null
	check("  and the menu is a dark box in a gold frame, like the windows",
		menu_box != null and menu_box.bg_color.v < 0.15 and menu_box.border_color.r > menu_box.border_color.b
		and menu_box.border_width_top >= 1 and game_theme.has_stylebox("hover", "PopupMenu"))
	stranger.free()
	mine.free()
	panel.free()

	# THE HUD SENDS EACH TO THE WINDOW THAT ALREADY DOES IT.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var built: Control = hud._build_players_panel()
	check("the HUD connects all three to its own windows",
		built.whisper_asked.is_connected(hud.whisper_player)
		and built.friend_asked.is_connected(hud.ask_to_be_friends)
		and built.trade_asked.is_connected(hud.trade_with))
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	check("  Whisper opens chat on the Whisper tab, Add friend asks from the Friends window,"
		+ " Trade offers from the Trade window",
		_func_body(hud_src, "func whisper_player(").contains("chat_panel.start_whisper(who)")
		and _func_body(hud_src, "func ask_to_be_friends(").contains("friends_panel.ask_from_elsewhere(who)")
		and _func_body(hud_src, "func trade_with(").contains("trade_panel.offer_to(active_character, who)"))
	check("  and opening the list is what builds and wires it",
		_func_body(hud_src, "func toggle_players(").contains("_build_players_panel()"))
	built.free()
	hud.free()

	# WHISPER: the same path as the chat log's name menu.
	var chat: Control = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	chat.whisper_to = chat.get_node_or_null("%chatto")
	for channel in chat.CHANNELS:
		chat._feeds[channel] = {"cursor": 0, "lines": [], "unread": false}
	chat.visible = true
	chat.start_whisper("  rowdy ")
	check("start_whisper opens the Whisper tab aimed at them",
		chat._channel == "private" and chat._whisper_with == "rowdy"
		and chat.whisper_to != null and chat.whisper_to.text == "rowdy",
		[chat._channel, chat._whisper_with])
	chat._menu_line = {"kind": "chat", "by": "other", "id": 5}
	chat._on_line_menu_id(chat.MENU_WHISPER)
	check("  and the chat log's own Whisper goes the same way", chat._whisper_with == "other")
	chat.free()

	# ADD FRIEND: the same checks as the box at the top of the Friends window.
	var friends: Control = (load("res://scene/ui/friends/friendspanel.tscn") as PackedScene).instantiate()
	friends.notice = friends.get_node_or_null("%friendsnotice")
	friends._name_check.compile(friends.NAME_PATTERN)
	var sent_self: bool = await friends.ask("Me_Myself")
	check("asking yourself is refused before anything is sent",
		not sent_self and friends.notice != null and friends.notice.text == "You cannot add yourself.",
		friends.notice.text if friends.notice != null else "no notice")
	var sent_bad: bool = await friends.ask("no spaces allowed")
	check("  and so is a name that cannot exist", not sent_bad)
	check("  the box at the top asks through the same function",
		_func_body(_code_src("res://src/ui/friends/friendspanel.gd"), "func _on_add_pressed(").contains("ask(add_entry.text)"))
	friends.free()

	# TRADE: the same request as a typed name - no slot, the server finds it.
	check("Trade from the list sends the typed-name offer",
		_func_body(_code_src("res://src/ui/trade/tradepanel.gd"), "func offer_to(").contains("_send_offer(who, -1)"))

	Api.username = was[0]
	Api.token = was[1]


func _test_the_stats_window_reads_cleanly() -> void:
	section("STATS WINDOW - two columns, short numbers, no lines between boxes")

	# Asked for on day 1: "1,007,892" in a small window, a separator line
	# between every box, and the level and XP floating in a gap.
	var short := func(n: int) -> String: return GameConstants.short_number(n)
	check("a big number is short: 1,007,892 is 1M, and never rounded up",
		short.call(1_007_892) == "1M" and short.call(1_999_999) == "1.9M"
		and short.call(12_345) == "12K" and short.call(998_501) == "998K"
		and short.call(45_600_000) == "45M" and short.call(1_500_000_000) == "1.5B",
		[short.call(1_007_892), short.call(1_999_999), short.call(12_345), short.call(998_501)])
	check("  a small one is written out, and a negative keeps its sign",
		short.call(9_391) == "9,391" and short.call(0) == "0" and short.call(-25_000) == "-25K",
		[short.call(9_391), short.call(-25_000)])

	var scene_text: String = FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn")
	var stats: Node = (load("res://scene/ui/statsscreen.tscn") as PackedScene).instantiate()
	var columns: Node = stats.find_child("statscontainer", true, false)
	check("two columns: level, experience and the pools beside the skills",
		columns is HBoxContainer and columns.find_child("leftcolumn", false, false) != null
		and columns.find_child("rightcolumn", false, false) != null
		and columns.find_child("leftcolumn", false, false).find_child("hpbar", true, false) != null
		and columns.find_child("rightcolumn", false, false).find_child("attackbar", true, false) != null)
	check("  with no separator lines - the boxes already separate",
		not scene_text.contains("HSeparator") and not scene_text.contains("VSeparator"))
	var tints: Dictionary = {}
	for key in ["hp", "stamina", "mana"]:
		var bar: ProgressBar = stats.find_child(key + "bar", true, false) as ProgressBar
		var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat if bar != null and bar.has_theme_stylebox_override("fill") else null
		var value: Label = stats.find_child(key + "value", true, false) as Label
		tints[key] = null
		if fill != null:
			tints[key] = fill.bg_color
		if value == null or value.get_parent() != bar:
			tints[key] = "number not inside the bar"
	check("  health red, stamina gold and mana blue, each number inside its bar",
		tints["hp"] is Color and tints["hp"].r > 0.6 and tints["hp"].g < 0.3
		and tints["stamina"] is Color and tints["stamina"].r > 0.6 and tints["stamina"].b < 0.3
		and tints["mana"] is Color and tints["mana"].b > 0.6 and tints["mana"].r < 0.4, tints)
	# The level sits in a hotbar slot (day 1, "make that a hotbar slot"): the
	# theme's PanelSocket, the same socket as the hotbar and every grid cell.
	var badge: PanelContainer = stats.find_child("levelbadge", true, false) as PanelContainer
	var level_value: Label = stats.find_child("levelvalue", true, false) as Label
	check("  the level sits in a hotbar slot, square, with the number inside it",
		badge != null and badge.theme_type_variation == &"PanelSocket"
		and badge.custom_minimum_size.x == badge.custom_minimum_size.y
		and level_value != null and badge.is_ancestor_of(level_value),
		str(badge.theme_type_variation) if badge else "no levelbadge")
	stats.free()

	var Stats: Script = load("res://src/ui/statsscreen.gd") as Script
	check("under the XP bar: how far, and how much is left to the next level",
		Stats.xp_next_text(9_391, 1_007_892, 29) == "0% · 998K to level 30"
		and Stats.xp_next_text(50, 100, 3) == "50% · 50 to level 4",
		Stats.xp_next_text(9_391, 1_007_892, 29))
	var code: String = _code_src("res://src/ui/statsscreen.gd")
	check("  and the exact figures are in the tooltips",
		_func_body(code, "func _update_progression(").contains("tooltip_text = exact")
		and _func_body(code, "func _set_bar_and_label(").contains("bar.tooltip_text"))
	print("  stats: short numbers, two columns, coloured pools, the next level in words")


func _test_bank_buttons_and_the_cooking_window() -> void:
	section("BANK AND COOKING - hotbar buttons, one row of fish, a window in the middle")

	# Asked for on day 1: Deposit and Withdraw in the hotbar's style; twelve
	# empty boxes under the fire; the cooking window opening in the corner.
	var theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	var socket: StyleBoxTexture = theme.get_stylebox("panel", &"PanelSocket") as StyleBoxTexture
	var normal: StyleBoxTexture = theme.get_stylebox("normal", &"ButtonSocket") as StyleBoxTexture
	var hover: StyleBoxTexture = theme.get_stylebox("hover", &"ButtonSocket") as StyleBoxTexture
	var pressed: StyleBoxTexture = theme.get_stylebox("pressed", &"ButtonSocket") as StyleBoxTexture
	check("the theme has a button drawn like a hotbar slot",
		theme.get_type_variation_base(&"ButtonSocket") == &"Button" and socket != null and normal != null
		and normal.texture == socket.texture and normal.texture.resource_path.ends_with("hotbarslot.png"))
	check("  which lights up under the pointer and darkens when pressed",
		hover != null and pressed != null and hover.texture == socket.texture
		and hover.modulate_color.v > normal.modulate_color.v and pressed.modulate_color.v < normal.modulate_color.v)
	var bank: Node = (load("res://scene/ui/bank/bankinventory.tscn") as PackedScene).instantiate()
	var dressed: Array = []
	for name_of in ["depositbuttons", "withdrawbutton"]:
		var b: Button = bank.find_child(name_of, true, false) as Button
		dressed.append(b != null and b.theme_type_variation == &"ButtonSocket" and not b.has_theme_stylebox_override("normal"))
	check("the bank's Deposit and Withdraw wear it", dressed == [true, true], dressed)
	bank.free()

	var Cooking: Script = load("res://src/ui/cooking/cookingscreen.gd") as Script
	check("one row of six, and a second only past six kinds of fish",
		Cooking.GRID_COLUMNS == 6 and Cooking.rows_for(0) == 1 and Cooking.rows_for(6) == 1
		and Cooking.rows_for(7) == 2 and Cooking.rows_for(12) == 2 and Cooking.rows_for(13) == 3)
	var joined: Array = Cooking.one_cell_per_kind([
		{"item_id": "rawmudfish", "quantity": 3}, {"item_id": "rawsilverfin", "quantity": 1},
		{"item_id": "rawmudfish", "quantity": 4}, {"item_id": "", "quantity": 9}])
	check("  one cell per kind: two stacks of mudfish are one cell of seven",
		joined == [{"item_id": "rawmudfish", "quantity": 7}, {"item_id": "rawsilverfin", "quantity": 1}], joined)

	var cooking: Control = (load("res://scene/ui/cooking/cookingscreen.tscn") as PackedScene).instantiate()
	add_child(cooking)
	var grid: Node = cooking.find_child("fishgrid", true, false)
	check("  the scene starts with one row", grid != null and grid.grid_width == 6 and grid.grid_height == 1
		and grid.get_child_count() == 6, [grid.grid_height if grid != null else -1])
	cooking.position = Vector2(58, 40)
	cooking.open_for_firepit(null, null)
	await get_tree().process_frame
	var wanted: Vector2 = PanelWindow.content_minimum(cooking)
	var middle: Vector2 = ((cooking.get_viewport_rect().size - cooking.size) * 0.5).floor()
	check("the cooking window is as big as what is in it, not 0x0",
		cooking.size.x >= 300.0 and cooking.size == wanted, [cooking.size, wanted])
	check("  and opens in the middle of the screen, wherever it was left",
		cooking.position == middle, [cooking.position, middle])
	var fire: Node2D = cooking.find_child("firepit", true, false) as Node2D
	var box: Control = cooking.find_child("firebox", true, false) as Control
	var fire_x: float = fire.position.x
	box.size = Vector2(box.size.x + 100.0, box.size.y)
	await get_tree().process_frame
	check("  a wider window keeps the fire in the middle of its box",
		is_equal_approx(fire.position.x, fire_x + 50.0), [fire_x, fire.position.x])
	# THE HEADER, day 1: it read "Cooking  Cooking 1  ×" with the title pushed
	# off centre. Now the level is a badge as wide as the ×, so the title sits
	# in the middle like BANK and INVENTORY.
	var badge: Label = cooking.find_child("skilllabel", true, false) as Label
	var title: Label = cooking.find_child("headerlabel", true, false) as Label
	var shut: Button = cooking.find_child("closebutton", true, false) as Button
	check("the cooking header is COOKING between a level badge and the ×, both as wide",
		title != null and title.text == "COOKING" and badge != null and badge.text.begins_with("Lv ")
		and shut != null and badge.get_index() == 0 and shut.get_index() == title.get_index() + 1
		and badge.size.x == shut.size.x
		and is_equal_approx(title.get_global_rect().get_center().x,
			(title.get_parent() as Control).get_global_rect().get_center().x),
		[badge.text if badge else "-", str(badge.size) if badge else "-", str(shut.size) if shut else "-"])
	grid.resize_grid(6, 2)
	check("a grid can be given another row", grid.get_child_count() == 12 and grid.columns == 6)
	cooking.queue_free()
	await get_tree().process_frame
	print("  bank and cooking: the hotbar's button, one row of fish, a sized and centred window")


func _test_the_tank_loop_takes_every_step() -> void:
	section("TANK - its own walk takes every step the other classes' walk takes")

	# Day 1: "tank not getting stamina xp". Tank replaces player.gd's
	# _physics_process() with an eased walk of its own, and that copy had
	# drifted: it never noted a key press (so the tank was "away" three minutes
	# after launch and earned no defence or agility XP), never paid agility for
	# sprinting or ground covered, never uncovered the map, and walked and
	# toggled its aura while chat was typed in. Each step is one player.gd
	# function now, and both loops must call every one of them.
	const STEPS := ["_stamp_input()", "_read_move_direction()", "_sprint_tick(",
		"_stop_sprint()", "_accrue_agility_from_travel(", "moved.emit(", "_tick_regen(",
		"_typing_in_ui()"]
	var player_src: String = _code_src("res://src/characters/player.gd")
	var tank_src: String = _code_src("res://src/characters/tank.gd")
	var base_loop: String = _func_body(player_src, "func _physics_process(")
	var tank_loop: String = ""
	for fn in ["func _physics_process(", "func _handle_movement(", "func _handle_moving(", "func _handle_idle("]:
		tank_loop += _func_body(tank_src, fn) + "\n"
	var base_missing: Array = []
	var tank_missing: Array = []
	for step in STEPS:
		if not base_loop.contains(step):
			base_missing.append(step)
		if not tank_loop.contains(step):
			tank_missing.append(step)
	check("the base loop is built from the shared steps", base_missing.is_empty(), base_missing)
	check("  and the tank's loop calls every one of them", tank_missing.is_empty(), tank_missing)
	check("  with no copy of its own of the keys or the sprint",
		not tank_src.contains("is_action_pressed(\"move_") and not tank_src.contains("_sprint_drain_accumulator +=")
		and not tank_src.contains("stamina - drain"))
	var stamp_at: int = tank_loop.find("_stamp_input()")
	check("  noting the key press before anything can return early",
		stamp_at != -1 and stamp_at < tank_loop.find("if is_dying:"))

	# AND WHAT THE STEPS DO, on a tank built outside the tree.
	var tank: Node = (load("res://src/characters/tank.gd") as GDScript).new()
	tank._last_input_ms = -1_000_000
	Input.action_press("move_right")
	tank._stamp_input()
	var noted: bool = not tank.is_afk()
	Input.action_release("move_right")
	check("a key press marks the tank as here, so its skill XP is earned", noted)
	tank.stamina = 100
	tank.sprint_agility_xp_per_sec = 0.0
	tank._sprint_tick(0.5)
	tank._sprint_tick(0.5)
	check("  a second of sprinting costs the tank stamina at the shared rate",
		tank.stamina == 100 - int(tank.sprint_stamina_drain_per_sec), tank.stamina)
	# Part-way to a point on both, so a _stop_sprint() that forgets either one
	# carries it into the next sprint.
	tank._is_sprinting = true
	tank._sprint_drain_accumulator = 0.5
	tank._sprint_agility_xp_accumulator = 0.5
	tank._stop_sprint()
	check("  and stopping clears what was banked toward the next point",
		not tank._is_sprinting and tank._sprint_drain_accumulator == 0.0
		and tank._sprint_agility_xp_accumulator == 0.0)
	tank.free()
	print("  tank: every step of the walk, shared - key presses, sprint, ground, map, typing")


func _test_the_first_five_minutes() -> void:
	section("FIRST FIVE MINUTES - eight buttons, a Controls card, a welcome, the right name")

	# Day 1, played as a brand-new player: fourteen small buttons on the bar,
	# nothing anywhere saying what a key does or where the Field is, a login
	# button that named another game, and two windows out of line.

	# ---- the bar: eight buttons, and two dropdowns for the rest ----
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var row: Array[String] = []
	for child in hud.get_node("%navbuttons").get_children():
		if child is Button:
			row.append(str(child.name))
	check("the bar is eight buttons, the everyday windows first",
		row == ["inventorybutton", "equipmentbutton", "statsbutton", "shopbutton", "mapbutton",
			"chatbutton", "socialbutton", "menubutton"], row)
	var held := func(menu_name: String) -> Array[String]:
		var out: Array[String] = []
		for b in hud.get_node("%" + menu_name).find_children("*", "Button", true, false):
			out.append(str(b.name))
		return out
	check("  Social holds Friends, Players, Guild, Trade and Kingdom",
		held.call("socialmenu") == ["friendsbutton", "playersbutton", "guildbutton", "tradebutton", "kingdombutton"],
		held.call("socialmenu"))
	check("  Menu holds Controls, Options, Switch character and Log out",
		held.call("systemmenu") == ["controlsbutton", "optionsbutton", "switchcharacterbutton", "logoutbutton"],
		held.call("systemmenu"))

	hud._wire_nav_buttons()
	var social: Control = hud.get_node("%socialmenu")
	var system: Control = hud.get_node("%systemmenu")
	check("  both shut until asked", not social.visible and not system.visible)
	(hud.get_node("%socialbutton") as Button).pressed.emit()
	check("pressing Social opens its dropdown", social.visible and not system.visible)
	(hud.get_node("%menubutton") as Button).pressed.emit()
	check("  Menu shuts it and opens its own", system.visible and not social.visible)
	(hud.get_node("%menubutton") as Button).pressed.emit()
	check("  a second press shuts it", not system.visible)
	(hud.get_node("%socialbutton") as Button).pressed.emit()
	(hud.get_node("%inventorybutton") as Button).pressed.emit()
	check("  and any button on the bar shuts it", not social.visible)
	(hud.get_node("%menubutton") as Button).pressed.emit()
	(hud.get_node("%controlsbutton") as Button).pressed.emit()
	check("a choice in a dropdown shuts it and opens what it names",
		not system.visible and hud.controls_panel != null and hud.controls_panel.visible)
	(hud.get_node("%socialbutton") as Button).pressed.emit()
	check("Escape shuts an open dropdown, and says when there was none",
		hud.close_nav_menus() and not social.visible and not hud.close_nav_menus())
	var hud_code: String = _code_src("res://src/ui/characterhud.gd")
	var esc_body: String = _func_body(hud_code, "func _unhandled_input(")
	var shut_at: int = esc_body.find("close_nav_menus()")
	check("  before it closes any window",
		shut_at != -1 and shut_at < esc_body.find("is_panel_open()"))
	check("  and a click anywhere else shuts it too",
		_func_body(hud_code, "func _input(").contains("_click_outside_nav_menus(event)"))

	var at: Vector2 = hud.nav_menu_position(Rect2(824, 676, 116, 30), Vector2(170, 178), Vector2(1280, 720))
	check("a dropdown opens above its button, right edges lined up, clear of the health bars",
		at == Vector2(770, 492), at)
	at = hud.nav_menu_position(Rect2(10, 676, 60, 30), Vector2(170, 178), Vector2(1280, 720))
	check("  and never off the left of the screen", at.x == 0.0, at)

	var social_button: Button = hud.get_node("%socialbutton") as Button
	var social_tip: String = social_button.tooltip_text
	hud._mark_trade_button(true, "caster")
	check("a trade waiting inside Social lights Social, and says what",
		social_button.text == "Social •" and social_button.tooltip_text == "Waiting for you: Trade",
		[social_button.text, social_button.tooltip_text])
	hud._mark_trade_button(false)
	check("  and goes out with it", social_button.text == "Social" and social_button.tooltip_text == social_tip,
		[social_button.text, social_button.tooltip_text])
	var hud_script: Script = hud.get_script()
	hud_script._asks_last = {"friends": {"count": 1, "newest": "medic", "at": 1}}
	hud._paint_ask_buttons()
	check("  a friend request lights it too", social_button.text == "Social •"
		and social_button.tooltip_text == "Waiting for you: Friends", social_button.tooltip_text)
	hud_script._forget_asks()
	hud._paint_ask_buttons()
	check("the bar says each window's key", (hud.get_node("%inventorybutton") as Button).tooltip_text.ends_with(
		"(%s)" % ControlsPanel.action_key("inventory_toggle"))
		and (hud.get_node("%controlsbutton") as Button).tooltip_text.ends_with("(%s)" % ControlsPanel.action_key("help_toggle")),
		(hud.get_node("%inventorybutton") as Button).tooltip_text)
	hud.free()

	# ---- the Controls card, read from the input map ----
	var card: ControlsPanel = (load("res://scene/ui/controls/controlspanel.tscn") as PackedScene).instantiate() as ControlsPanel
	add_child(card)
	card.open_controls()
	var keys: Dictionary = {}
	for i in range(0, card.key_grid.get_child_count() - 1, 2):
		keys[(card.key_grid.get_child(i) as Label).text] = (card.key_grid.get_child(i + 1) as Label).text
	check("the Controls card has a line for every row", keys.size() == ControlsPanel.ROWS.size(), keys.size())
	check("  Space or right-click attacks, Shift sprints, E uses, H is the card",
		keys.get("Attack, aiming with the mouse") == "Space or right-click" and keys.get("Sprint") == "Hold Shift"
		and keys.get("Use the shop, bank, fire or fishing spot") == "E" and keys.get("This card") == "H", keys)
	check("  W A S D walk, and the hotbar is 1 to 0",
		keys.get("Move") == "W A S D or arrows" and keys.get("Use the item on a hotbar key") == "1 to 0",
		[keys.get("Move"), keys.get("Use the item on a hotbar key")])
	var leaked: Array = []
	for how in keys.values():
		if String(how).contains("_") or String(how).contains("?"):
			leaked.append(how)
	check("  every key it names is bound - no action name shown as words", leaked.is_empty(), leaked)
	# EVERY KEY THE GAME BINDS IS ON THE CARD. A new action added to
	# project.godot with no line here would be a key nobody is told about.
	var named: Dictionary = {}
	for spec in ControlsPanel.ROWS:
		named[String(spec[1])] = true
	var untold: Array[String] = []
	for prop in ProjectSettings.get_property_list():
		var key_path: String = str(prop.name)
		if not key_path.begins_with("input/") or key_path.begins_with("input/ui_"):
			continue
		var action: String = key_path.trim_prefix("input/")
		if not (named.has(action) or (action.begins_with("move_") and named.has("move"))):
			untold.append(action)
	check("  and no key the game binds is missing from it", untold.is_empty(), untold)
	await get_tree().process_frame
	var middle: Vector2 = ((card.get_viewport_rect().size - card.size) * 0.5).floor()
	check("  in the middle of the screen, as big as what is on it",
		card.position == middle and card.size == PanelWindow.content_minimum(card)
		and card.size.x >= 400.0, [card.position, middle, card.size])
	check("  with no welcome on it", not card.welcome_box.visible and not card.got_it_button.visible
		and card.header_label.text == "CONTROLS")

	# ---- the welcome, once ----
	var was_seen_path: String = ControlsPanel.seen_path
	ControlsPanel.seen_path = "user://_suite_seen.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ControlsPanel.seen_path))
	check("a computer that has never played has not seen the welcome", not ControlsPanel.has_seen_welcome())
	card.open_welcome()
	check("the welcome says where to go, then the keys, then Got it",
		card.header_label.text == "WELCOME TO ELUSION" and card.welcome_box.visible
		and card.welcome_text.text.contains("Field") and card.got_it_button.visible
		and card.footer_label.text == "Press H any time to see these keys again.", card.footer_label.text)
	check("  and is marked seen the moment it shows", ControlsPanel.has_seen_welcome())
	card.got_it_button.pressed.emit()
	check("Got it closes it", not card.visible)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ControlsPanel.seen_path))
	ControlsPanel.seen_path = was_seen_path
	card.queue_free()
	check("the welcome comes up in town and nowhere else - never in this suite",
		hud_script.welcome_belongs_in("res://scene/elusion.tscn")
		and not hud_script.welcome_belongs_in("res://scene/field.tscn")
		and not hud_script.welcome_belongs_in("res://scene/tests/tests.tscn"))
	check("  offered when a character arrives, and only if not yet seen",
		_func_body(hud_code, "func set_active_character(").contains("_offer_welcome_soon()")
		and _func_body(hud_code, "func offer_welcome(").contains("ControlsPanel.has_seen_welcome()")
		and _func_body(hud_code, "func offer_welcome(").contains("welcome_belongs_in("))

	# ---- the login button names this game ----
	var login_text: String = FileAccess.get_file_as_string("res://scene/ui/menus/loginmenu.tscn")
	check("the login button says Enter Elusion",
		str(_node_prop_in_scene("res://scene/ui/menus/loginmenu.tscn",
			"centercontainer/mainpanel/margincontainer/vboxcontainer/loginform/loginbutton", "text")) == "Enter Elusion")
	check("  and no screen anywhere says Elysium", not login_text.contains("Elysium")
		and not hud_code.contains("Elysium"))

	# ---- the Gear window's title, like the others ----
	var inv_size: Variant = _node_prop_in_scene("res://scene/ui/inventory/inventory.tscn",
		"mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/headerlabel", "theme_override_font_sizes/font_size")
	var eq_path := "mainpanel/margincontainer/vboxcontainer/headerpanel/hboxcontainer/headerlabel"
	check("the Gear window's title is EQUIPMENT, centred, the size of INVENTORY's",
		str(_node_prop_in_scene("res://scene/ui/equipment/equipmentpanel.tscn", eq_path, "text")) == "EQUIPMENT"
		and int(_node_prop_in_scene("res://scene/ui/equipment/equipmentpanel.tscn", eq_path, "horizontal_alignment")) == HORIZONTAL_ALIGNMENT_CENTER
		and _node_prop_in_scene("res://scene/ui/equipment/equipmentpanel.tscn", eq_path, "theme_override_font_sizes/font_size") == inv_size,
		inv_size)

	# ---- Character Stats: the left column from top to bottom ----
	var stats: Control = (load("res://scene/ui/statsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(stats)
	stats.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var frame: Control = stats.find_child("leftcolumn", true, false) as Control
	var level_row: Control = stats.find_child("levelrow", true, false) as Control
	var mana_row: Control = stats.find_child("manastat", true, false) as Control
	var top_gap: float = level_row.get_global_rect().position.y - frame.get_global_rect().position.y
	var bottom_gap: float = frame.get_global_rect().end.y - mana_row.get_global_rect().end.y
	check("Character Stats: LEVEL sits at the top of its box, Mana at the bottom",
		top_gap <= 16.0 and bottom_gap <= 16.0 and absf(top_gap - bottom_gap) <= 4.0, [top_gap, bottom_gap])
	stats.queue_free()
	print("  first five minutes: eight buttons, every key on a card, a welcome once, Enter Elusion")


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

	# ---- a note is reach-gated like a sanction ----
	check("a note is offered wherever a kick is",
		offer.call("mod", "player", true).note and not offer.call("mod", "mod", false).note)

	# ---- what goes on the wire ----
	# THE SEARCH AND THE FILTERS ARE THE SERVER'S NOW - see "THE SERVER PAGES"
	# at the top of staffpanel.gd. So what is worth pinning here is the question
	# as it leaves: encoded, and with nothing empty in it, because `q=` is a
	# search for nothing and `before=0` is not a cursor.
	check("a query is encoded and keeps its order",
		panel_script.build_query({"show": "all", "q": "a b&c", "limit": 50}) == "?show=all&q=a%20b%26c&limit=50",
		panel_script.build_query({"show": "all", "q": "a b&c", "limit": 50}))
	check("an empty search is left out, not sent as q=",
		panel_script.build_query({"show": "online", "q": "", "limit": 50}) == "?show=online&limit=50")
	check("a zero cursor is left out, not sent as before=0",
		panel_script.build_query({"player": "rowdy", "before": 0, "limit": 25}) == "?player=rowdy&limit=25")
	check("nothing at all is no query at all", panel_script.build_query({}) == "")

	# ---- what comes back ----
	# THE TWO JSON TRAPS: numbers arrive as floats, and the last page's cursor
	# arrives as null - which str() makes "<null>", a name to page after.
	var last_page: Dictionary = panel_script.read_page(
		{"accounts": [{"username": "a"}, "junk"], "more": true, "next_after": null}, "accounts", "next_after")
	check("a null cursor is no cursor", last_page.cursor == null, last_page)
	check("and no cursor means no next page, whatever `more` says", last_page.more == false, last_page)
	check("only dictionaries are rows", last_page.rows.size() == 1, last_page.rows)
	var log_page: Dictionary = panel_script.read_page(
		{"actions": [], "more": true, "next_before": 12.0}, "actions", "next_before")
	check("a float cursor is an int", log_page.cursor is int and log_page.cursor == 12 and log_page.more, log_page)
	check("an answer that is not a dictionary is an empty page",
		panel_script.read_page("oops", "accounts", "next_after").rows.is_empty())

	# ---- the record, in words ----
	var tally: Dictionary = {"note": 1.0, "warn": 3.0, "ban": 2.0, "kick": 1.0, "unban": 4.0}
	check("a record reads bans, kicks, warnings, notes - in that order, with plurals",
		panel_script.describe_record(tally) == "2 bans · 1 kick · 3 warnings · 1 note",
		panel_script.describe_record(tally))
	check("the list row leaves the notes out - a note is not a sanction",
		panel_script.describe_record(tally, panel_script.ROW_RECORD_KINDS) == "2 bans · 1 kick · 3 warnings")
	check("a clean record says nothing", panel_script.describe_record({}) == ""
		and panel_script.describe_record(null) == "")

	check("a ban reads as a sentence, with the reason kept whole",
		panel_script.describe_entry({"by": "themod", "action": "ban", "target": "rowdy",
			"detail": "3 days: language"}) == "themod banned rowdy - 3 days: language")
	check("a warning",
		panel_script.describe_entry({"by": "themod", "action": "warn", "target": "rowdy",
			"detail": "spam"}) == "themod warned rowdy - spam")
	check("no detail, no dash",
		panel_script.describe_entry({"by": "thedev", "action": "unban", "target": "rowdy"})
		== "thedev lifted rowdy's ban")
	check("a kind this build has never heard of still says who, what and whom",
		panel_script.describe_entry({"by": "boss", "action": "smite", "target": "rowdy", "detail": "x"})
		== "boss smite rowdy - x")
	check("a log line about a player opens that player",
		panel_script.target_is_account({"action": "kick", "target": "rowdy"}))
	check("a line about a guild does not pretend it is an account",
		not panel_script.target_is_account({"action": "guild_rename", "target": "Shared"}))
	check("nor does a teleport of everyone",
		not panel_script.target_is_account({"action": "teleport", "target": "everyone"}))
	check("the count says how much of the match is loaded",
		panel_script.describe_count(50, 1204, 12) == "50 of 1,204 · 12 online",
		panel_script.describe_count(50, 1204, 12))
	check("and just the total once it all is",
		panel_script.describe_count(12, 12, 3) == "12 accounts · 3 online"
		and panel_script.describe_count(1, 1, 0) == "1 account · 0 online",
		panel_script.describe_count(12, 12, 3))

	# ---- presence text, against the SERVER'S clock ----
	var now := 1_000_000
	check("online reads as online", panel_script.describe_presence({"online": true}, now) == "Online now")
	check("minutes", panel_script.describe_presence({"last_seen_at": now - 300}, now) == "Last seen 5 min ago",
		panel_script.describe_presence({"last_seen_at": now - 300}, now))
	check("hours", panel_script.describe_presence({"last_seen_at": now - 7200}, now) == "Last seen 2 h ago")
	check("days", panel_script.describe_presence({"last_seen_at": now - 3 * 86400}, now) == "Last seen 3 days ago")
	check("no heartbeat at all is just offline", panel_script.describe_presence({"last_seen_at": 0}, now) == "Offline")

	# ---- the scene carries every node the script reaches for ----
	# DERIVED FROM THE SCRIPT, not a list typed here. The list this replaced was
	# the panel's twenty-four nodes as of the day it was written, and the panel
	# grew twenty more - a hand list checks the old panel and passes.
	var scene: Node = (load("res://scene/ui/staff/staffpanel.tscn") as PackedScene).instantiate()
	var node_ref := RegEx.new()
	node_ref.compile("= %([a-z][a-z0-9_]+)")
	var missing: Array = []
	var asked: int = 0
	for m in node_ref.search_all(_code_only(FileAccess.get_file_as_string("res://src/ui/staff/staffpanel.gd"))):
		asked += 1
		if scene.get_node_or_null("%" + m.get_string(1)) == null:
			missing.append(m.get_string(1))
	check("staffpanel.tscn has every node staffpanel.gd uses",
		missing.is_empty() and asked >= 40, "missing: %s (%d asked)" % [missing, asked])
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

	# AND THE BUTTONS THEMSELVES. _wire_nav_buttons() connects by UNIQUE NAME and
	# skips anything it cannot find, so a renamed button - or one whose "unique
	# name" box was unticked - is a dead button with no error. Nine of them sit
	# in the Social and Menu dropdowns now, not on the row.
	var absent: Array = []
	for wanted in hud.NAV_BUTTON_NAMES:
		if not (hud.get_node_or_null("%" + wanted) is Button):
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
			"friendstitle", "friendsrequests", "friendsnotice", "friendscount"]],
		["res://scene/ui/equipment/equipmentpanel.tscn",
			["equipclosebutton", "equipdamagevalue", "equipspeedvalue", "equiparmourvalue",
			"equipsoakvalue", "equippreview", "equippreviewbox", "equippreviewhint",
			"equiphealthbonusvalue", "equipmanabonusvalue", "equipdamagebonusvalue"]],
		["res://scene/ui/guild/guildpanel.tscn",
			["guildrows", "guildtitle", "guildtag", "guildcount", "guildentry",
			"guildactionbutton", "actionpanel", "guildclosebutton",
			"guildnotice", "footerbox",
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
	check("and guild - which is live; see _test_guild_chat_is_open()",
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
	for n in range(1, Hotbar.SLOT_COUNT + 1):
		var slot: Node = bar.find_child("slot%d" % n, true, false)
		if slot == null:
			lost.append("slot%d" % n)
			continue
		# AND THE KEY NUMBER IS A NODE NOW, not baked into the empty art - so
		# it is still there once a slot has something in it. That was the whole
		# complaint: a filled slot used to stop saying which key it was.
		#
		# READ OFF THE KEY, not off the slot's number. The tenth slot is fired
		# by 0, so str(n) would demand it say "10" - a number no key has.
		var key: Label = slot.get_node_or_null("keylabel") as Label
		var wanted: String = OS.get_keycode_string(Hotbar.SLOT_KEYS[n - 1]) \
			if n - 1 < Hotbar.SLOT_KEYS.size() else "?"
		if key == null or key.text != wanted:
			keyless.append("slot%d says %s, its key is %s" % [n,
				key.text if key != null else "nothing", wanted])
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

	# ---- colour is yours, rank is a badge ----
	# THIS SECTION USED TO SAY THE OPPOSITE: "staff keep their rank colour
	# whatever the slider says". While rank was a colour that was the only way
	# to keep it true, and the price was an Options slider that silently did
	# nothing for staff - which is how it was reported. Rank is worn ABOVE the
	# name now (the crown, or MOD / DEV), so the colour is free for everybody,
	# and what has to stay true is the badge, which only the server's rank sets.
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	# THE PLATE WITHOUT THE PLAYER. Adding a warrior to the tree runs all of
	# player.gd's _ready() - camera, pets, the save - for a check about a label.
	body._setup_nameplate()
	check("this client's own name is the colour its player chose",
		body._nameplate_colour() == Settings.name_colour(), body._nameplate_colour())
	check("a body told about somebody else is drawn in THEIR colour, not ours",
		body._nameplate_colour(300) == NameTag.colour(300)
		and NameTag.colour(300) != NameTag.colour(20))
	var plate: Label = body.get("_nameplate")
	var crown_node: TextureRect = body.get("_nameplate_crown")
	var badge_node: Label = body.get("_nameplate_badge")
	check("the plate, its crown and its badge are built", plate != null and crown_node != null and badge_node != null)
	if plate != null and crown_node != null and badge_node != null:
		var worn: Dictionary = {}
		for staff_rank in ["player", "mod", "dev", "owner"]:
			body.set_nameplate("somebody", staff_rank)
			worn[staff_rank] = [
				plate.get_theme_color("font_color") == Settings.name_colour(),
				crown_node.visible, badge_node.visible, badge_node.text,
				badge_node.get_theme_color("font_color") == Api.colour_for_role(staff_rank)]
		check("staff choose their colour like anybody - the slider is not ignored for them",
			worn["mod"][0] and worn["dev"][0] and worn["owner"][0] and worn["player"][0], worn)
		check("the owner wears the crown and nothing else",
			worn["owner"][1] and not worn["owner"][2], worn["owner"])
		check("a mod wears MOD, in the mod colour", not worn["mod"][1] and worn["mod"][2]
			and worn["mod"][3] == "MOD" and worn["mod"][4], worn["mod"])
		check("a dev wears DEV, in the dev colour", worn["dev"][2] and worn["dev"][3] == "DEV"
			and worn["dev"][4], worn["dev"])
		check("a player wears nothing - which is what makes the other three stand out",
			not worn["player"][1] and not worn["player"][2], worn["player"])
		# THE TAG SURVIVES A NEW COLOUR. Picking a colour repainted the plate
		# through set_nameplate() with no tag, and the tag vanished until the
		# next broadcast poll put it back.
		# SIGNED IN AS SOMEBODY, whoever this machine last signed in as. The
		# repaint reads Api.username, and a machine whose last session was
		# logged out has none - which blanked the plate and failed this check
		# on a clean state rather than on a defect.
		var was_user: String = Api.username
		Api.username = "somebody"
		body.set_nameplate("somebody", "player", "LIFERS")
		body._on_setting_changed("name_hue", 0.0)
		check("picking a new colour keeps the guild tag on the plate",
			plate.text.contains("[LIFERS]"), plate.text)
		body._on_identity_changed("somebody", "mod")
		check("and so does a rank change", plate.text.contains("[LIFERS]"), plate.text)
		Api.username = was_user

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
	# beside it, which each player chooses.
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
	check("the nameplate and every list agree on the art and on who wears it",
		NameTag.CROWN_PATH == crown_file and NameTag.CROWN_RANK == body.NAMEPLATE_CROWN_RANK
		and NameTag.CROWN_SIZE == Vector2(26, 15))

	# ONE FUNCTION DRAWS A NAME IN EVERY LIST. The crown used to be a constant
	# in chat, another in the friends list and a third over the head - three
	# chances for one to point at nothing, and a missing [img] fails silently.
	for path in ["res://src/ui/chat/chatpanel.gd", "res://src/ui/friends/friendspanel.gd",
			"res://src/ui/players/playerspanel.gd", "res://src/ui/guild/guildpanel.gd"]:
		var body_src: String = _code_only(FileAccess.get_file_as_string(path))
		check("%s draws names through nametag.gd" % path.get_file(),
			body_src.contains('preload("res://src/shared/nametag.gd")')
			and body_src.contains("NameTag."), path)
		check("%s no longer paints a name by rank" % path.get_file(),
			not body_src.contains("colour_for_role("), path)

	# AND IT IS ACTUALLY DRAWN, not merely named. Built into a real row.
	var row := HBoxContainer.new()
	var drawn: Label = NameTag.add_to(row, "boss", "owner", 200)
	var crowns: Array = row.find_children("*", "TextureRect", true, false)
	check("an owner's row carries the crown, before the name",
		crowns.size() == 1 and (crowns[0] as TextureRect).texture != null
		and row.get_child(0) == crowns[0] and row.get_child(1) == drawn)
	check("and the name is in the owner's own colour, not a rank colour",
		drawn.get_theme_color("font_color") == NameTag.colour(200))
	row.free()
	row = HBoxContainer.new()
	drawn = NameTag.add_to(row, "helper", "mod", null)
	var mod_badge: Label = row.get_node_or_null("badge") as Label
	check("a mod's row carries MOD in the mod colour",
		mod_badge != null and mod_badge.text == "MOD"
		and mod_badge.get_theme_color("font_color") == Api.colour_for_role("mod"))
	check("and somebody who never chose a colour is drawn in the default one",
		drawn.get_theme_color("font_color") == Settings.name_colour(float(Settings.DEFAULTS["name_hue"])))
	row.free()
	check("chat's crown is the same art at the same size",
		NameTag.bbcode("boss", "owner", 10).begins_with("[img=26x15]%s[/img]" % crown_file),
		NameTag.bbcode("boss", "owner", 10))
	check("chat's badge is a word in the rank colour, then the name in theirs",
		NameTag.bbcode("helper", "dev", 10).contains("DEV")
		and NameTag.bbcode("helper", "dev", 10).contains(Api.colour_for_role("dev").to_html(false))
		and NameTag.bbcode("helper", "dev", 10).contains(NameTag.colour(10).to_html(false)))
	check("a hue off the wire that is not on the wheel is drawn as the default, not trusted",
		NameTag.colour(999) == NameTag.colour(null) and NameTag.colour("red") == NameTag.colour(null))

	# ---- the colour travels ----
	# THE SERVER HOLDS IT NOW (users.name_hue), so the slider's colour is what
	# everybody else sees too. Checked without writing the player's own
	# options file: the suite never moves anybody's settings.
	var here: int = wrapi(int(round(float(Settings.get_value("name_hue")))), 0, 360)
	var was_synced: Variant = Api.get("_synced_name_hue")
	Api.adopt_name_hue({"name_hue": here})
	check("after a login the server's hue is the one held, so nothing echoes back up",
		Api.name_hue_to_push() == -1, Api.name_hue_to_push())
	Api.set("_synced_name_hue", (here + 5) % 360)
	check("and a hue the server does not hold yet is pushed", Api.name_hue_to_push() == here,
		Api.name_hue_to_push())
	Api.set("_synced_name_hue", was_synced)
	var api_src: String = _code_only(FileAccess.get_file_as_string("res://src/systems/api.gd"))
	var fn := func(name: String) -> Array:
		var at: int = _first_code_index(api_src, "func %s(" % name, 0)
		return [at, _first_code_index(api_src, "\nfunc ", at + 1)]
	var span: Array = fn.call("adopt_name_hue")
	check("the server's colour wins at login: it is written into Settings",
		_within(_first_code_index(api_src, 'Settings.set_value("name_hue"', span[0]), span[1]) != -1)
	span = fn.call("push_name_hue_soon")
	check("and the slider's colour is sent to the server",
		_within(_first_code_index(api_src, 'put("/api/account/name-colour"', span[0]), span[1]) != -1)
	span = fn.call("_adopt_session")
	check("a login adopts it", _within(_first_code_index(api_src, "adopt_name_hue(", span[0]), span[1]) != -1)
	span = fn.call("probe_and_resume")
	check("and so does resuming a saved session",
		_within(_first_code_index(api_src, "adopt_name_hue(", span[0]), span[1]) != -1)
	body.free()

	# ---- the heartbeat: only a 401 signs anyone out ----
	check("a live session beats ok", Api.heartbeat_verdict({"ok": true, "status": 200}) == "ok")
	check("a 401 is a kick, a ban or an expiry", Api.heartbeat_verdict({"ok": false, "status": 401}) == "revoked")
	# A SERVER RESTART MUST NOT BE A MASS KICK.
	for status in [0, 404, 500, 503]:
		check("HTTP %d signs nobody out" % status,
			Api.heartbeat_verdict({"ok": false, "status": status}) == "offline")
	# THE BEAT IS THE BROADCAST POLL, AND THIS CHECK USED TO NAME THE WRONG
	# CONSTANT.
	#
	# It asserted HEARTBEAT_SECONDS * 3 <= 45 and passed for months while the
	# thing it describes was not happening: Api.heartbeat() is called from
	# exactly one place in this project - the 401 handler - and nothing fires
	# it on a timer. So the arithmetic was sound and about a request nobody
	# made, and sessions.last_seen_at was stamped once at login and never
	# again. Forty-five seconds later the friends list, the guild roster and
	# the players menu all read the player as offline. It showed up in game as
	# a guild panel saying "0 online of 1" to the only member, who was reading
	# it at the time.
	#
	# The stamp rides the broadcast poll now (app.py, stamp_presence), so THIS
	# is the interval that has to fit inside the window - and it is the one a
	# timer actually drives.
	var beat: float = load("res://src/ui/characterhud.gd").BROADCAST_POLL_SECONDS
	check("three beats fit inside the server's 45 s online window",
		beat * 3.0 <= 45.0, beat)
	# READ FRESH, because `hud_src` is not in scope here and reaching for a
	# variable from another section is how a check ends up measuring whichever
	# file happened to be loaded last.
	var hud_text: String = FileAccess.get_file_as_string(
		"res://src/ui/characterhud.gd")
	check("and the beat is the poll a timer really runs",
		hud_text.contains("timer.wait_time = BROADCAST_POLL_SECONDS"),
		"a constant nothing schedules is a comment with a number in it")

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
	"res://scene/projectiles/meteor.tscn",
	"res://scene/projectiles/spinningaxe.tscn",
	"res://scene/projectiles/dynamite.tscn",
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


# =============================================================================
# ONLY LEVELLING UP REFILLS THE POOLS
# =============================================================================
# _fill_all_resources() sets hp = max_hp, mana = max_mana, stamina = max_stamina
# unconditionally. There is exactly one moment in this game where that is the
# right thing to do, and it is levelling up.
#
# IT USED TO SIT IN THE `level` SETTER AS WELL, and that is the interesting part,
# because it did nothing detectable and was still a defect.
#
# CharacterData.load_character_state() assigns every key of SAVEABLE_STATS in
# turn, and `level` is the FIRST key in that dictionary. So the setter fired on
# every load and refilled all three pools - and then hp, max_hp, mana, max_mana,
# stamina and max_stamina, all further down the SAME dictionary, overwrote the
# refill a few iterations later.
#
# So the entire "what was full stays full, what was hurt stays hurt" rule -
# the death penalty, the server's healing reconciler, the reason a loading screen
# is not a healing potion - was standing on THE INSERTION ORDER OF A CONST
# DICTIONARY IN A DIFFERENT FILE. Put `hp` above `level`, or add any key before
# it, and every login quietly becomes a free full heal.
#
# There is no symptom to notice. The bug's entire tell is "the game feels
# generous", months later, and the server would see it as an unexplained heal on
# an honest player - which is E-9's false positive, arriving from the client's
# own code.
#
# That is why this section checks the CALL SITES rather than the key order.
# Pinning the order would pin the coincidence; what is actually wanted is that
# nothing but level_up() ever refills, and then the order cannot matter.

func _test_only_levelling_up_refills() -> void:
	section("REFILLING - only levelling up fills all three pools")

	var player_src: String = FileAccess.get_file_as_string(
		"res://src/characters/player.gd")
	check("player.gd is readable", player_src != "")
	if player_src == "":
		return
	var code: String = _code_only(player_src)

	# COUNTED IN CODE, AND THE DEFINITION DOES NOT COUNT AS A CALL. `func
	# _fill_all_resources() -> void:` contains the string, which is the exact
	# mistake `hud.count("_note_server_contact()")` made - the definition
	# counting itself, and removing a real call still leaving the total right.
	var call_sites: int = code.count("_fill_all_resources()") \
		- code.count("func _fill_all_resources()")
	check("_fill_all_resources() has exactly one call site", call_sites == 1,
		"%d found - every one of them is a free full heal" % call_sites)

	# AND IT IS INSIDE level_up(). A count alone passes on one call in the wrong
	# function, which is precisely the state this section exists to forbid.
	var level_up_at: int = _first_code_index(code, "func level_up(", 0)
	var next_func_at: int = _first_code_index(code, "\nfunc ", level_up_at + 1)
	check("level_up() exists", level_up_at != -1)
	# SEARCHED FROM level_up(), NOT FROM ZERO. From zero the first hit is
	# `func _fill_all_resources() -> void:` - the definition, hundreds of lines
	# earlier - and the check went red on correct code the first time it ran.
	# The definition-counts-as-a-call trap, twice in one section.
	var fill_at: int = _first_code_index(code, "_fill_all_resources()", level_up_at)
	check("and the one call site is inside it",
		level_up_at != -1 and _within(fill_at, next_func_at) != -1,
		"call at %d, level_up() spans %d..%d" % [fill_at, level_up_at, next_func_at])

	# THE SETTER. It must still recompute the maxima - that is what it is for,
	# and the Remote Inspector case its comment describes depends on it - and it
	# must not touch the pools.
	var setter_at: int = _first_code_index(code, "var level: int = 1:", 0)
	var xp_at: int = _first_code_index(code, "var xp: int = 0", 0)
	check("the level setter is where it was", setter_at != -1)
	var setter_body: String = code.substr(setter_at, maxi(xp_at - setter_at, 0)) \
		if setter_at != -1 and xp_at > setter_at else ""
	check("the level setter still recomputes the maxima",
		setter_body.contains("_recompute_max_stats()"))
	check("THE LEVEL SETTER DOES NOT REFILL THE POOLS",
		not setter_body.contains("_fill_all_resources()"),
		"load_character_state() assigns `level` first, so this fires on every load")

	# _ready() RESTORES, IT DOES NOT FILL. The long comment in _ready() explains
	# why at length; this is the machine-readable half of it.
	var ready_at: int = _first_code_index(code, "func _ready() -> void:", 0)
	var after_ready: int = _first_code_index(code, "\nfunc ", ready_at + 1)
	check("_ready() exists", ready_at != -1)
	check("_ready() does not fill the pools",
		_within(_first_code_index(code, "_fill_all_resources()", ready_at),
			after_ready) == -1)

	# THE THREE CONDITIONALS, BY POSITION. was_full_* has to be measured against
	# the SAVED maxima, so it must come before _recompute_max_stats() replaces
	# them, and the assignments must come after.
	var was_full_at: int = _first_code_index(code, "var was_full_hp:", ready_at)
	var recompute_at: int = _first_code_index(code, "_recompute_max_stats()", ready_at)
	var assign_at: int = _first_code_index(code, "hp = max_hp if was_full_hp", ready_at)
	check("fullness is measured before the maxima are recomputed",
		was_full_at != -1 and recompute_at != -1 and was_full_at < recompute_at,
		"measuring after would compare the saved hp against the NEW maximum")
	check("and the restore happens after",
		assign_at != -1 and recompute_at < assign_at)
	for vital in ["mana = max_mana if", "stamina = max_stamina if"]:
		check("%s... is conditional too" % vital.split(" ")[0],
			_within(_first_code_index(code, vital, ready_at), after_ready) != -1)

	# THE OTHER HALF OF THE OLD ACCIDENT, asserted so it cannot rot into being
	# load-bearing again: the save really does carry all six, so the conditional
	# restore above has real numbers to work with.
	var saveable: Dictionary = CharacterData.SAVEABLE_STATS
	for key in ["hp", "max_hp", "mana", "max_mana", "stamina", "max_stamina", "level"]:
		check("SAVEABLE_STATS carries %s" % key, saveable.has(key))

	print("  %d call site(s) for _fill_all_resources(), setter clean" % call_sites)


# =============================================================================
# THE SHOPKEEPER WAVES ONCE
# =============================================================================
# A wave is a GREETING, not a state. It used to loop for as long as the player
# stood in the shop, and the script's own header explained why that was fine:
# "THE STILL FRAME IS FRAME 0 OF THE WAVE ... we never need a second, one-frame
# idle animation."
#
# THAT WAS TRUE OF THE DESIGN AND FALSE OF THE SHEET. The ten frames actually
# shipped in art/npc/shopkeeper.png began mid-wave - frame 0 was the arm fully
# extended, hand out - so the "still figure" the comment promised was a man
# frozen with his arm in the air, and the wave had no rest pose to return to. It
# could only loop, because looping was the only state those frames could express.
#
# A comment cannot fail, so nobody compared the sentence to the pixels for as
# long as it existed. This section does, which is why two of these checks read
# images rather than strings.
#
# The artist's full set fixes it at the source: a seven-frame idle, and an
# eleven-frame wave that begins at rest, raises, waves and lowers. The wave does
# not loop; when it ends, animation_finished puts the idle back.
#
# THE WAVE'S LAST FRAME IS NOT THE REST POSE - it is the arm still up at the
# shoulder, ended mid-lower so it cuts cleanly back to the idle. So "stop on the
# last frame" is not an option here, and there is a check saying so, because it
# is the obvious simplification and it reintroduces the frozen-arm bug.

func _test_the_shopkeeper_waves_once() -> void:
	section("THE SHOPKEEPER - one wave per arrival, then back to the idle")

	var packed: PackedScene = load("res://scene/walls/shophouse.tscn") as PackedScene
	check("shophouse.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return

	var house: Node = packed.instantiate()
	add_child(house)
	var sprite: AnimatedSprite2D = house.get_node_or_null(
		"interiorfurniture/shopvendor/animatedsprite2d") as AnimatedSprite2D
	check("the shopkeeper sprite is where the scene says it is", sprite != null)
	if sprite == null:
		house.queue_free()
		return

	var sf: SpriteFrames = sprite.sprite_frames
	check("it has SpriteFrames", sf != null)
	if sf == null:
		house.queue_free()
		return

	check("there is an idle at all", sf.has_animation(&"idledown"))
	check("and a wave", sf.has_animation(&"wavedown"))
	check("the idle loops", sf.get_animation_loop(&"idledown"))
	check("THE WAVE DOES NOT LOOP", not sf.get_animation_loop(&"wavedown"),
		"a looping animation never emits animation_finished, so it can never end")
	check("the idle is the artist's seven frames",
		sf.get_frame_count(&"idledown") == 7, sf.get_frame_count(&"idledown"))
	check("the wave is the artist's eleven frames",
		sf.get_frame_count(&"wavedown") == 11, sf.get_frame_count(&"wavedown"))
	check("the scene rests on the idle, not the wave",
		sprite.animation == &"idledown", sprite.animation)

	# REGIONS READ OFF THE TEXTURE, NOT OFF THE LOOP COUNTER. The first draft of
	# this recorded `seen[i * 64]` - the index being iterated rather than the
	# region just fetched - so the set was eighteen wide whatever the scene said,
	# and the check could not fail. Sabotage found it. Same family as a count
	# that includes the function's own definition.
	var regions_ok: bool = true
	var columns: Dictionary = {}
	for pair in [[&"idledown", 7, 0], [&"wavedown", 11, 7]]:
		for i in range(int(pair[1])):
			var tex: AtlasTexture = sf.get_frame_texture(pair[0], i) as AtlasTexture
			if tex == null:
				regions_ok = false
				continue
			if tex.region != Rect2((int(pair[2]) + i) * 64, 0, 64, 64):
				regions_ok = false
			columns[tex.region.position.x] = true
	check("every frame reads its own column of the sheet", regions_ok)
	check("all eighteen columns are used exactly once", columns.size() == 18,
		"%d distinct columns" % columns.size())

	# AGAINST THE PIXELS. "the still frame is frame 0 of the wave" is exactly the
	# claim the old comment made about a sheet that did not support it.
	var wave_first: Image = _frame_image(sf, &"wavedown", 0)
	var idle_first: Image = _frame_image(sf, &"idledown", 0)
	var wave_last: Image = _frame_image(sf, &"wavedown",
		sf.get_frame_count(&"wavedown") - 1)
	check("the wave begins on the pose the idle rests on",
		_images_match(idle_first, wave_first, 20),
		"the cut from idle into wave would jump")
	check("the wave's LAST frame is NOT that rest pose",
		not _images_match(wave_last, wave_first, 20),
		"if it were, stopping on it would do - and this whole change is pointless")

	# BEHAVIOUR, WITH THE TREE RUNNING. Calling the handler by hand proves the
	# handler; only waiting proves the SIGNAL, and the signal is the mechanism.
	var probe: AnimatedSprite2D = AnimatedSprite2D.new()
	probe.sprite_frames = sf
	var area: Area2D = Area2D.new()
	area.add_child(probe)
	probe.set_script(load("res://src/world/shopkeeperanim.gd"))
	add_child(area)

	# _ready() DOES NOT RUN UNTIL THE TREE TICKS. Without this the node never
	# enters the tree, every check below reads the SpriteFrames' default
	# animation instead of the script's, and they all pass blind - which is how
	# the sabotage "boot straight into the wave" first stayed green.
	await get_tree().process_frame
	check("the probe is really in the tree, so _ready() ran", probe.is_inside_tree())
	check("it starts on the idle", probe.animation == &"idledown", probe.animation)

	var body: CharacterBody2D = CharacterBody2D.new()
	body.add_to_group("player")
	probe._on_body_entered(body)
	check("walking up plays the wave", probe.animation == &"wavedown",
		probe.animation)

	probe.speed_scale = 30.0
	await get_tree().create_timer(0.6).timeout
	check("THE WAVE ENDS ON ITS OWN AND THE IDLE COMES BACK",
		probe.animation == &"idledown", probe.animation)
	check("and it is playing the idle rather than stopped on a frame",
		probe.animation == &"idledown" and probe.is_playing())

	var rock: CharacterBody2D = CharacterBody2D.new()
	probe._on_body_entered(rock)
	check("an enemy crossing the shop does not get waved at",
		probe.animation == &"idledown", probe.animation)

	var anim_src: String = FileAccess.get_file_as_string(
		"res://src/world/shopkeeperanim.gd")
	check("leaving is not wired to anything - the wave is finite already",
		not _code_only(anim_src).contains("body_exited.connect"))
	check("the finished handler returns to the idle rather than stopping",
		_code_only(anim_src).contains("_play_idle()"))

	body.free()
	rock.free()
	area.queue_free()
	house.queue_free()
	print("  one wave per arrival, 11 frames, then the 7-frame idle")


func _frame_image(sf: SpriteFrames, anim: StringName, index: int) -> Image:
	var tex: AtlasTexture = sf.get_frame_texture(anim, index) as AtlasTexture
	return tex.get_image() if tex != null else null


func _images_match(a: Image, b: Image, tolerance: int) -> bool:
	"""True when at most `tolerance` pixels differ. Not equality: the artist's
	idle and wave rest poses differ by a few pixels of hand detail, which is a
	redraw rather than a different pose."""
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	var differing: int = 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				differing += 1
				if differing > tolerance:
					return false
	return true


# =============================================================================
# A CHEST AND A FIREPIT YOU CANNOT WALK THROUGH
# =============================================================================
# Both were Area2D scenes and nothing else. An Area2D DETECTS; it does not push
# back - so "is the player close enough to open me" was the only question either
# of them could answer, and a player walked straight through the chest and stood
# in the fire.
#
# The fix is one StaticBody2D per scene, on the default layer 1 ("ground"),
# which is what every solid prop in scene/crypt/ uses and what the TileMapLayer
# collision uses. The player masks 1, 2 and 5; every enemy masks 1 as well, so
# both props stop enemies too, which is the answer you want for a fire.
#
# NOT ON A LAYER THE PROP'S OWN Area2D MASKS. Otherwise the chest detects its
# own blocker and treats it as somebody standing there. Both scripts also filter
# on the player group, so that is belt and braces - but a mask that overlaps is
# the kind of thing that gets "tidied" into place later, so it is checked.
#
# WHY THE SHAPES ARE THE SIZES THEY ARE, since a .tscn cannot hold a comment -
# the parser rejects '#' outright, which is why no scene in this project carries
# one, and which cost a load failure to rediscover:
#
#   chest    the art occupies x 8..24, y 12..27 of its 32x32 frame, so 17 wide.
#            The shape covers the lower 10 of those 16 rows - the box - and
#            leaves the lid walk-behind, the same proportion scene/crypt/ uses.
#   firepit  drawn almost straight down, so the whole ring IS its footprint and
#            there is no walk-behind half. Measured through the sprite's own
#            (2, -2) offset and 1.1504664 / 1.0584878 scale, the ring lands at
#            roughly x -8.4..13.5, y -8.4..10.7. The rectangle is INSET from
#            that - 20 x 17, not 22 x 19 - because the ring is round and a
#            rectangle's corners would block empty air.
#
# SIZED, NOT SCALED, on both: the size lives in the RectangleShape2D and scale
# stays (1,1) on the body and the shape. See "Scale the sprite, size the shape"
# in CLAUDE.md - a scaled collision node gives up the broad phase's cheap
# rejection, and the firepit's sprite is already carrying a 1.15 scale that must
# not reach the shape.
#
# THE CONTROL IS THE WHOLE TEST. Driving a body at a wall and finding it stopped
# proves nothing on its own - a mover that never moved would pass. So each prop
# is driven twice, once with the blocker and once with its shape disabled, and
# the check is that the two answers DIFFER in the right direction.

const BLOCKING_PROPS := {
	"res://scene/interactables/bankchest.tscn": "the bank chest",
	"res://scene/interactables/firepit.tscn": "the firepit",
}


func _test_props_block_the_player() -> void:
	section("SOLID PROPS — the chest and the firepit push back")

	# READ OFF THE REAL PLAYER, not typed in here. A second copy of "19" would
	# agree with itself forever while the classes moved underneath it.
	var player_layer: int = int(_scene_root_prop(
		"res://scene/characters/warrior.tscn", "collision_layer", 0))
	var player_mask: int = int(_scene_root_prop(
		"res://scene/characters/warrior.tscn", "collision_mask", 0))
	check("the player's own layer and mask are readable",
		player_layer != 0 and player_mask != 0,
		"layer %d mask %d" % [player_layer, player_mask])
	if player_layer == 0 or player_mask == 0:
		return

	for path in BLOCKING_PROPS:
		var what: String = BLOCKING_PROPS[path]
		var packed: PackedScene = load(path) as PackedScene
		check("%s loads" % what, packed != null and packed.can_instantiate())
		if packed == null or not packed.can_instantiate():
			continue

		var prop: Node2D = packed.instantiate() as Node2D
		var body: StaticBody2D = prop.get_node_or_null("body") as StaticBody2D
		check("%s has a solid body" % what, body != null,
			"an Area2D detects, it does not push back")
		if body == null:
			prop.free()
			continue

		var shape_node: CollisionShape2D = body.get_node_or_null("collision") \
			as CollisionShape2D
		check("%s's body carries a shape" % what,
			shape_node != null and shape_node.shape != null)
		if shape_node == null or shape_node.shape == null:
			prop.free()
			continue

		check("%s blocks on a layer the player actually collides with" % what,
			(body.collision_layer & player_mask) != 0,
			"body layer %d vs player mask %d" % [body.collision_layer, player_mask])

		# THE PROP MUST NOT SEE ITS OWN BLOCKER.
		var root_mask: int = int(prop.get("collision_mask")) if "collision_mask" in prop else 0
		check("%s cannot detect its own blocker" % what,
			(body.collision_layer & root_mask) == 0,
			"body layer %d is inside the Area2D's mask %d" % [body.collision_layer, root_mask])

		check("%s's body is not scaled" % what, body.scale == Vector2.ONE, body.scale)
		check("%s's shape node is not scaled" % what,
			shape_node.scale == Vector2.ONE, shape_node.scale)

		# AIMED AT THE ART, NOT AT THE SHAPE, and this is the whole point.
		# The first version drove the mover at `shape_node.position.y` - so
		# parking the shape a hundred pixels off the sprite moved the TEST with
		# it and stayed green. A check that aims at the thing it is checking
		# cannot find it missing. Third time today; see the column-counter in
		# the shopkeeper section and the call count above.
		#
		# _art_ground_y() reads the sprite's lowest non-transparent row and
		# transforms it through the sprite's own offset and scale, so the aim
		# point is where the prop MEETS THE GROUND however the shape is set up.
		var aim: float = _art_ground_y(prop)
		check("%s's footprint covers where its art meets the ground" % what,
			_shape_covers(shape_node, aim), "art ground line at y=%.1f, shape at "
			% aim + "y=%.1f" % shape_node.position.y)

		var blocked: float = await _walk_into(prop, player_layer, player_mask, aim)
		shape_node.disabled = true
		var through: float = await _walk_into(prop, player_layer, player_mask, aim)
		shape_node.disabled = false

		check("%s stops a body walking into it" % what, blocked < 0.0,
			"ended at x=%.1f, which is past the prop" % blocked)
		check("and the same body goes straight through when the shape is off" % [],
			through > 20.0,
			"ended at x=%.1f with collision disabled - the drive never moved, so "
			% through + "the check above proves nothing")
		check("%s: blocked and unblocked differ" % what, through - blocked > 20.0,
			"blocked %.1f vs through %.1f" % [blocked, through])

		prop.free()

	print("  drove a player-shaped body into each prop, with and without its shape")


func _walk_into(prop: Node2D, layer: int, mask: int, at_y: float) -> float:
	"""Put `prop` in a bare world, drive a player-shaped body east into it from
	x = -40, and return where the body ended up. Positive means it got past."""
	var world: Node2D = Node2D.new()
	add_child(world)

	# CANCEL THE PROP'S OWN position SO prop-local IS world here. Both of these
	# scenes carry one - the chest sits at (0, -8) and the firepit at (0, -11) -
	# and `at_y` arrives in the prop's space. Without this the mover is driven
	# eight or eleven pixels below the footprint and sails past, which is
	# exactly what happened: it read as "the shapes do not block" when the real
	# fault was the test standing in the wrong coordinate system. The first
	# version hid it by aiming at the shape, so the same error cancelled on
	# both sides.
	var holder: Node2D = Node2D.new()
	holder.position = -prop.position
	world.add_child(holder)
	holder.add_child(prop)

	var mover: CharacterBody2D = CharacterBody2D.new()
	mover.collision_layer = layer
	mover.collision_mask = mask
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 6.0
	var shape: CollisionShape2D = CollisionShape2D.new()
	shape.shape = circle
	mover.add_child(shape)
	world.add_child(mover)
	mover.position = Vector2(-40.0, at_y)

	# A FULL SECOND OF PHYSICS at 80 ticks - the project's rate - which is far
	# more than the 80px it needs to cross the prop entirely.
	for _i in range(80):
		mover.velocity = Vector2(120.0, 0.0)
		mover.move_and_slide()
		await get_tree().physics_frame

	var landed: float = mover.position.x
	holder.remove_child(prop)
	world.queue_free()
	return landed


func _scene_root_prop(path: String, prop: String, fallback: Variant) -> Variant:
	"""A root node's property, read WITHOUT instantiating the scene.

	Instantiating a class scene here would run player.gd's _ready(), which loads
	a character, touches CharacterData and spawns a pet. get_state() is the same
	read-only door src/tools/atlasaudit.gd uses on the levels."""
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return fallback
	var state: SceneState = packed.get_state()
	if state.get_node_count() == 0:
		return fallback
	for i in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, i) == prop:
			return state.get_node_property_value(0, i)
	return fallback


func _art_ground_y(prop: Node2D) -> float:
	"""Where this prop's ART meets the ground, in the prop's own space.

	The lowest row of the sprite's first frame that has any alpha in it, pushed
	back through the sprite's offset and scale, then lifted 3px so the answer is
	inside a footprint rather than exactly on its edge. Deliberately measured
	from the pixels and not from the 32x32 cell - both of these sit well inside
	their frame, and the frame's bottom row is empty air for each of them."""
	var sprite: AnimatedSprite2D = prop.get_node_or_null("animatedsprite2d") \
		as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return 0.0
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	if tex == null:
		return 0.0
	var img: Image = tex.get_image()
	if img == null:
		return 0.0
	var bottom_row: int = -1
	for y in range(img.get_height() - 1, -1, -1):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.0:
				bottom_row = y
				break
		if bottom_row != -1:
			break
	if bottom_row == -1:
		return 0.0
	var in_texture: float = float(bottom_row) + 0.5 - img.get_height() / 2.0
	var in_prop: float = sprite.position.y \
		+ (sprite.offset.y + in_texture) * sprite.scale.y
	return in_prop - 3.0


func _shape_covers(node: CollisionShape2D, y: float) -> bool:
	"""Does this shape span `y`, measured in the shape's parent's space?"""
	var extent: float = 0.0
	if node.shape is RectangleShape2D:
		extent = (node.shape as RectangleShape2D).size.y * 0.5
	elif node.shape is CircleShape2D:
		extent = (node.shape as CircleShape2D).radius
	elif node.shape is CapsuleShape2D:
		extent = (node.shape as CapsuleShape2D).height * 0.5
	else:
		return true  # an unmeasured shape type is not evidence of a hole
	return absf(y - node.position.y) <= extent


# =============================================================================
# NOTHING SHADOWS A PROPERTY OF ITS OWN BASE CLASS
# =============================================================================
# `var size: int = ...` inside a Control warns at parse time - SHADOWED_VARIABLE_
# BASE_CLASS - and that warning comes from the EDITOR. It does not reach a
# headless run, which was proved twice: neither `--check-only` (it cannot even
# load a script that names an autoload) nor `--headless --editor --quit` printed
# a single warning line for a file that warns the moment the project is opened.
#
# So this is the same structural blind spot _test_no_unused_parameters() exists
# for, and it leaked the same way: two warnings arrived from a project being
# opened, one of them `var size` in guildpanel.gd shadowing Control.size.
#
# NOT A HARDCODED LIST OF PROPERTY NAMES. ClassDB is the engine's own answer -
# get_instance_base_type() resolves through a chain of `extends SomeClassName`
# to the native base, and class_get_property_list() says what that base owns. A
# list typed in here would agree with itself forever while Godot moved.
#
# WHAT IT FOUND ON ITS FIRST RUN: three `for name in ...` loops in this very
# file, all shadowing Node.name. And renaming one of them exposed the second
# half of why shadowing is worth failing on - a line further down the same loop
# still said `name`, which had been reading the LOOP variable and would silently
# have started reading the test runner node's own name instead. A shadowed
# property does not announce itself when the shadow is removed; it just starts
# answering a different question.
#
# Covers `var`, `@export var` and `for`. Function parameters are left to
# _test_no_unused_parameters()'s sibling problem and are not checked here.

func _test_nothing_shadows_its_base_class() -> void:
	section("SHADOWING — no local hides a property its base class already has")

	var offenders: Array[String] = []
	var props: Dictionary = {}
	var scanned: Array[int] = [0]
	_scan_shadowing("res://src", offenders, props, scanned)
	offenders.sort()

	check("nothing declares a name its own base class already owns",
		offenders.is_empty(), "\n         ".join(offenders))
	check("and the scan actually read the project",
		scanned[0] > 50, "%d scripts scanned" % scanned[0])

	# THE PARSER, TESTED DIRECTLY, because the paragraph above this section
	# explains the rule by quoting `var size` at the start of a line - and a
	# scanner that read prose would report its own explanation. Sixth time in
	# this file that a text check could have matched the comment describing the
	# thing it forbids, so it gets an assertion rather than a hope.
	check("a comment that merely says 'var size' is not a declaration",
		_declared_name("\t# var size: int = 0   <- the rule, not a use") == "",
		_declared_name("\t# var size: int = 0   <- the rule, not a use"))
	check("but a real declaration still is",
		_declared_name("\tvar size: int = 0") == "size")
	check("and so is a for loop variable",
		_declared_name("\tfor name in things:") == "name")

	print("  %d scripts, %d base classes consulted through ClassDB"
		% [scanned[0], props.size()])


func _scan_shadowing(dir_path: String, offenders: Array[String],
		props: Dictionary, scanned: Array[int]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_shadowing(full, offenders, props, scanned)
		elif entry.ends_with(".gd"):
			_scan_one_for_shadowing(full, offenders, props, scanned)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_one_for_shadowing(path: String, offenders: Array[String],
		props: Dictionary, scanned: Array[int]) -> void:
	var script: Script = load(path) as Script
	if script == null:
		return
	scanned[0] += 1
	var base: String = script.get_instance_base_type()
	if base == "" or not ClassDB.class_exists(base):
		return
	if not props.has(base):
		var owned: Dictionary = {}
		for entry in ClassDB.class_get_property_list(base, false):
			owned[str(entry.get("name", ""))] = true
		props[base] = owned
	var owned_here: Dictionary = props[base]

	var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
	for i in range(lines.size()):
		var declared: String = _declared_name(lines[i])
		if declared == "" or not owned_here.has(declared):
			continue
		offenders.append("%s:%d  '%s' shadows %s.%s"
			% [path.replace("res://", ""), i + 1, declared, base, declared])


func _declared_name(line: String) -> String:
	"""The name a line declares, or "" if it declares nothing.

	NO COMMENT STRIPPING, AND THAT IS A MEASURED DECISION RATHER THAN AN
	OMISSION. Every other text check in this file blanks comments first, because
	the paragraph explaining a rule reliably contains the rule's own text - and
	the paragraph above this function quotes `var size` for exactly that reason.

	It is not needed HERE because the match is anchored: the line must BEGIN
	with `var `, `@export var ` or `for ` once indentation is gone, and a
	comment begins with `#`. A stripper was written in anyway, and sabotaging it
	left the whole project green - which is how it was found to be doing
	nothing. Removed rather than kept as a comment claiming it was load-bearing.

	The anchoring is what carries it, so that is what the checks above assert.
	Loosen the match to a contains() and they go red."""
	var trimmed: String = line.strip_edges()
	var rest: String = ""
	for prefix in ["var ", "@export var ", "for "]:
		if trimmed.begins_with(prefix):
			rest = trimmed.substr(prefix.length())
			break
	if rest == "":
		return ""
	var stop: int = rest.length()
	for ch in [" ", ":", "=", ",", "\t", "("]:
		var at: int = rest.find(ch)
		if at != -1 and at < stop:
			stop = at
	return rest.substr(0, stop).strip_edges()


# =============================================================================
# EVERY ext_resource NAMES A FILE THAT IS ACTUALLY THERE
# =============================================================================
# The gap between the two checks either side of it. _test_script_references()
# covers path-only SCRIPT references; _test_no_import_cache_references() catches
# a reference that has already DEGRADED into a res://.godot/imported path. This
# one covers the state in between and before both: a scene still naming a source
# file that has been deleted.
#
# WHY NOTHING NOTICES ON THE MACHINE WHERE IT HAPPENS. Measured on 4.6.1 by
# deleting art/tiles/c92.png with .godot/imported left alone:
#
#   probe                       source present      source deleted
#   FileAccess.file_exists()    true                FALSE
#   ResourceLoader.exists()     true                true
#   load(path) != null          true                true
#
# So the engine goes on serving the baked .ctex and the game looks perfect - to
# the one person who cannot see the problem, which is whoever deleted the file.
# .godot/ is gitignored, so a clone has nothing to serve and the scene loses its
# texture. That is the c92.png disaster exactly: one line ninety lines into an
# 85KB scene file, and 112 painted cells with nothing to draw.
#
# Same family as the table in CLAUDE.md showing load() returns a non-null Script
# for a file that will not compile. The convenient probe is the one that lies;
# the one that moves is the one nobody reaches for first.
#
# PATHS ARE READ BETWEEN THE QUOTES, never split on whitespace. This project has
# art/enemy/perfect bushmage.png, art/tiles/black tile.png, art/tiles/cyclops
# wall with eyes.png and art/tiles/tiles1_Animation 1_0.png. Splitting on spaces
# invents missing files out of every one of them - which has already happened
# once in this project, to `git ls-files` without -z, and produced a confident
# report of 86 missing files when the real answer was 20.
#
# art/pack/ REFERENCES SKIP WHEN THE PACK IS ABSENT, like every other check that
# needs it, and stay real checks on any machine that has it.

func _test_every_resource_reference_exists() -> void:
	section("REFERENCES — every ext_resource names a file that exists")

	var missing: Array[String] = []
	var checked: Array[int] = [0, 0]  # [references checked, files read]
	_scan_resource_refs("res://scene", missing, checked)
	_scan_resource_refs("res://data", missing, checked)
	_scan_resource_refs("res://art", missing, checked)
	_scan_resource_refs("res://assets", missing, checked)
	missing.sort()

	check("every ext_resource path resolves to a real file", missing.is_empty(),
		"\n         ".join(missing))
	# THRESHOLDS NEAR THE REAL FIGURES, NOT TOKEN ONES. The first draft asked
	# for 200 references across 50 files, and deleting the `res://scene` scan
	# entirely left it green - data/, art/ and assets/ alone clear a token
	# threshold comfortably. A count check that survives losing the largest of
	# four scan roots is not checking the scan. 897 across 416 today.
	check("and the scan actually read something",
		checked[0] > 600 and checked[1] > 250,
		"%d references across %d files - a scan root has gone quiet"
			% [checked[0], checked[1]])

	# THE PROBE ITSELF, asserted, because the whole check rests on one fact that
	# is easy to "simplify" into uselessness. A reader who swaps FileAccess for
	# ResourceLoader.exists() would leave every check above green for ever.
	check("FileAccess is what answers 'is the source file there'",
		FileAccess.file_exists("res://project.godot"))
	check("and a path that was never real is answered honestly",
		not FileAccess.file_exists("res://art/this-file-has-never-existed.png"))

	print("  %d ext_resource references across %d scenes and resources"
		% [checked[0], checked[1]])


func _scan_resource_refs(dir_path: String, missing: Array[String],
		checked: Array[int]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_resource_refs(full, missing, checked)
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			_check_one_resource_file(full, missing, checked)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_one_resource_file(path: String, missing: Array[String],
		checked: Array[int]) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		return
	checked[1] += 1
	for line in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var named: String = _quoted_after(line, "path=")
		if named == "" or not named.begins_with("res://"):
			continue
		if named.begins_with("res://art/pack/") and not _pack_present():
			continue
		checked[0] += 1
		if not FileAccess.file_exists(named):
			missing.append("%s  names  %s" % [path.replace("res://", ""), named])


func _quoted_after(line: String, key: String) -> String:
	"""The quoted value following `key` on this line, spaces and all.

	Between the quotes, never split on whitespace - see the header above for the
	four filenames in this project that contain spaces and the one time that
	mistake was made for real."""
	var at: int = line.find(key)
	if at == -1:
		return ""
	var open_quote: int = line.find("\"", at + key.length())
	if open_quote == -1:
		return ""
	var close_quote: int = line.find("\"", open_quote + 1)
	if close_quote == -1:
		return ""
	return line.substr(open_quote + 1, close_quote - open_quote - 1)


# =============================================================================
# THE PANEL YOU SEE IS THE PANEL YOU GRAB
# =============================================================================
# PanelWindow puts its eight grips on `window` - the scene's root Control - and
# clamps THAT to the screen when you drag the header. What the player sees is
# the PanelContainer drawn inside it. The two have to be the same rectangle, or
# every guarantee PanelWindow makes is made about something nobody can see.
#
# Two of sixteen were not, measured by reading every panel scene's first child:
#
#   inventory.tscn   mainpanel at offsets (0, -24, 0, +42) - drawn 24px above
#                    and 42px below its window. The grips sat inside the drawn
#                    border, and the header-drag clamp kept the WINDOW on screen
#                    while the header itself could be pushed 24px off the top.
#                    Reported as "the arrows on the box are not lining up" and
#                    "it should still stay on screen" - one bug, two symptoms.
#   staffpanel.tscn  root anchored to the centre with NO offsets - a zero-size
#                    window, a point - and a 660x470 panel drawn around it. The
#                    grips were eight handles stacked on one pixel.
#
# Both fixed by moving the geometry onto the window and making the panel fill
# it, so nothing on screen moved: inventory's window is 3..415 now, which is
# exactly where its panel was already being drawn.
#
# THE LIST OF PANELS IS DERIVED, NOT TYPED. Any scene under scene/ui whose root
# script calls PanelWindow.attach(self, ...) is checked, so a seventeenth panel
# is covered the day it exists rather than the day somebody remembers.
#
# AND IT HAS TO HOLD WHILE YOU RESIZE, not just at rest. A full-rect panel
# cannot be smaller than its own contents, so dragging the window below that
# made the panel overflow the grips again. _minimum() asks the content now -
# PanelWindow.content_minimum() - so the window cannot be made smaller than what
# it holds. The last checks below build a panel and ask.

func _test_panels_fill_their_window() -> void:
	section("PANEL GEOMETRY — the drawn panel is exactly where the grips are")

	var panels: Array[String] = []
	_find_window_scenes("res://scene/ui", panels)
	panels.sort()
	check("the PanelWindow scenes were found by reading the scripts",
		panels.size() >= 14, "%d found" % panels.size())

	var wrong: Array[String] = []
	for path in panels:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			wrong.append("%s does not load" % path)
			continue
		var state: SceneState = packed.get_state()
		var first: int = _first_child_index(state)
		if first == -1:
			wrong.append("%s has no child under its root" % path)
			continue
		var geo: Dictionary = {}
		for key in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom",
				"offset_left", "offset_top", "offset_right", "offset_bottom"]:
			geo[key] = 0.0
		for i in range(state.get_node_property_count(first)):
			var pname: String = state.get_node_property_name(first, i)
			if geo.has(pname):
				geo[pname] = float(state.get_node_property_value(first, i))
		var fills: bool = geo["anchor_left"] == 0.0 and geo["anchor_top"] == 0.0 \
			and geo["anchor_right"] == 1.0 and geo["anchor_bottom"] == 1.0 \
			and geo["offset_left"] == 0.0 and geo["offset_top"] == 0.0 \
			and geo["offset_right"] == 0.0 and geo["offset_bottom"] == 0.0
		if not fills:
			wrong.append("%s  %s  anchors (%s,%s,%s,%s) offsets (%s,%s,%s,%s)" % [
				path.get_file(), state.get_node_name(first),
				geo["anchor_left"], geo["anchor_top"], geo["anchor_right"], geo["anchor_bottom"],
				geo["offset_left"], geo["offset_top"], geo["offset_right"], geo["offset_bottom"]])
	check("every panel fills its window exactly - no overhang, no zero-size window",
		wrong.is_empty(), "\n         ".join(wrong))

	# WHILE RESIZING. Build a window whose content needs 300 x 250 and ask.
	var host: Control = Control.new()
	var frame: PanelContainer = PanelContainer.new()
	var content: Control = Control.new()
	content.custom_minimum_size = Vector2(300, 250)
	frame.add_child(content)
	host.add_child(frame)
	# THROUGH _minimum(), NOT AROUND IT. The first draft asked the static
	# content_minimum() directly and handed that to resize_rect() - so it proved
	# the helper worked and never proved anything USED it. Sabotaging _minimum()
	# to ignore the content left it green. What resize and fit actually consult
	# is _minimum(), so that is what gets asked.
	var probe: PanelWindow = PanelWindow.new()
	probe.window = host
	var needed: Vector2 = probe._minimum()
	check("the window's minimum includes what its content needs",
		needed.x >= 300.0 and needed.y >= 250.0, needed)
	var squeezed: Rect2 = PanelWindow.resize_rect(Rect2(0, 0, 400, 400),
		Vector2(-390, -390), PanelWindow.EDGE_RIGHT | PanelWindow.EDGE_BOTTOM,
		needed, Vector2(1920, 1080))
	check("so dragging it smaller stops where the content would start to overflow",
		squeezed.size.x >= 300.0 and squeezed.size.y >= 250.0, squeezed.size)
	frame.visible = false
	check("and a hidden child does not hold the window open",
		PanelWindow.content_minimum(host) == Vector2.ZERO,
		PanelWindow.content_minimum(host))
	host.free()

	print("  %d panel scenes, every one filling its window" % panels.size())


func _find_window_scenes(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_find_window_scenes(full, out)
		elif entry.ends_with(".tscn"):
			var script_path: String = str(_scene_root_script_path(full))
			if script_path != "" and _code_only(
					FileAccess.get_file_as_string(script_path)).contains(
					"PanelWindow.attach(self"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _scene_root_script_path(path: String) -> String:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return ""
	var state: SceneState = packed.get_state()
	if state.get_node_count() == 0:
		return ""
	for i in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, i) == "script":
			var s: Script = state.get_node_property_value(0, i) as Script
			return s.resource_path if s != null else ""
	return ""


func _first_child_index(state: SceneState) -> int:
	"""The first node whose parent is the root, or -1."""
	for i in range(1, state.get_node_count()):
		if str(state.get_node_path(i, true)) == ".":
			return i
	return -1


# =============================================================================
# A FIRE YOU LIGHT OPENS THE COOKING SCREEN BY ITSELF
# =============================================================================
# A cold firepit used to take two presses: one to kindle it, and a second, after
# the flame caught, to say "yes, I want to cook". Every firepit goes out again a
# second after you finish, so nobody kindles one for any other reason - the
# second press only ever meant "the thing I just did". Now the kindle ends in the
# cooking screen.
#
# THE RULE THAT MATTERS IS WHERE THE CALL LIVES. It is at the end of _kindle(),
# not inside light_fire(), because light_fire() is also what _ready() calls on a
# pit authored lit and what a quest script reaches. Putting the panel there would
# open the cooking screen at anybody who walked into an area with a camp already
# burning. So the last check here calls light_fire() on its own and asserts the
# panel stays shut.
#
# BEHAVIOURAL, WITH THE KINDLE ACTUALLY RUN. The firepit is instanced for real, a
# stand-in HUD is put in the "hud" group, and the suite waits out KINDLE_SECONDS.
# The stand-in is proven to receive a direct call FIRST - otherwise every "the
# panel was not opened" check below would pass on a stand-in that could never
# have been reached.

func _test_a_lit_fire_opens_cooking() -> void:
	section("FIREPIT — kindling a fire ends in the cooking screen")

	var packed: PackedScene = load("res://scene/interactables/firepit.tscn") as PackedScene
	check("firepit.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return

	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node\nvar opened: Array = []\n" \
		+ "func open_cooking(pit, who) -> void:\n\topened.append([pit, who])\n"
	fake_script.reload()
	var hud: Node = Node.new()
	hud.set_script(fake_script)
	hud.add_to_group("hud")
	add_child(hud)

	var cook: CharacterBody2D = CharacterBody2D.new()
	cook.add_to_group("player")
	add_child(cook)

	# THE CONTROL. Prove the stand-in is reachable before trusting its silence.
	var probe_pit: Area2D = packed.instantiate() as Area2D
	add_child(probe_pit)
	await get_tree().process_frame
	probe_pit.player_in_range = cook
	probe_pit._open_cooking()
	check("the stand-in HUD really does receive open_cooking()",
		hud.opened.size() == 1, hud.opened.size())
	probe_pit.queue_free()
	hud.opened.clear()

	# THE ONE PRESS.
	var pit: Area2D = packed.instantiate() as Area2D
	add_child(pit)
	await get_tree().process_frame
	check("a firepit starts cold", not pit.is_lit)
	pit.player_in_range = cook
	pit._kindle()
	check("kindling does not open the screen before the fire has caught",
		hud.opened.is_empty(), hud.opened.size())
	await get_tree().create_timer(float(pit.KINDLE_SECONDS) + 0.3).timeout
	check("once the kindle finishes the fire is lit", pit.is_lit)
	check("AND THE COOKING SCREEN OPENS, ONCE, WITHOUT A SECOND PRESS",
		hud.opened.size() == 1, hud.opened.size())
	check("for this fire and this player",
		hud.opened.size() == 1 and hud.opened[0][0] == pit and hud.opened[0][1] == cook)
	check("and the fire knows its panel is up", pit._is_open)
	pit.queue_free()
	hud.opened.clear()

	# WALKING AWAY MID-KINDLE CANCELS ALL OF IT.
	var left: Area2D = packed.instantiate() as Area2D
	add_child(left)
	await get_tree().process_frame
	left.player_in_range = cook
	left._kindle()
	left.player_in_range = null
	await get_tree().create_timer(float(left.KINDLE_SECONDS) + 0.3).timeout
	check("walk away during the kindle and no screen opens", hud.opened.is_empty(),
		hud.opened.size())
	check("and no fire is left burning behind you", not left.is_lit)
	left.queue_free()

	# light_fire() ON ITS OWN IS THE _ready()/QUEST PATH, AND MUST STAY QUIET.
	var authored: Area2D = packed.instantiate() as Area2D
	add_child(authored)
	await get_tree().process_frame
	authored.player_in_range = cook
	authored.light_fire()
	await get_tree().process_frame
	check("a fire lit by anything but the player's own kindle opens nothing",
		hud.opened.is_empty(),
		"a camp authored lit would pop the cooking screen at everyone arriving")
	authored.queue_free()

	cook.queue_free()
	hud.queue_free()
	print("  one press on a cold fire: kindle, then the cooking screen")


# =============================================================================
# THE INVENTORY WEARS THE HOTBAR'S SLOTS, AND THE TRASH IS A SLOT TOO
# =============================================================================
# Asked for as "use hotbar slots for inventory boxes, just no numbers". The
# hotbar's socket - art/images/hotbarslot.png, nine-sliced at 7px - is now a
# named theme style, PanelSocket, and inventoryslot.tscn wears it. Every grid
# that InventoryContainer builds uses that one slot scene, so the inventory,
# the bank, the loot bag and the cooking screen all changed together, which is
# the point: one slot, everywhere a slot appears.
#
# "JUST NO NUMBERS" is structural rather than a setting. The hotbar draws its
# key number as a separate `keylabel` Label on top of the socket; the socket art
# itself has no number in it. So the inventory slot gets the art and not the
# label, and a check says the label stays out.
#
# THE HOTBAR STILL HAS ITS OWN COPY of the socket style, inline in hotbar.tscn,
# and that is deliberate: it was not asked to change. The price is two copies
# that could drift, so they are compared here - texture and all eight margins -
# and the day one is edited without the other, this goes red.
#
# THE TRASH was a TextureButton with a sentence hung off it at a fixed offset.
# It is a socket now, the same size as a slot, in the inventory and the bank,
# and it glows red while something it would accept is over it.

func _test_slots_wear_the_hotbar_socket() -> void:
	section("SLOTS — the hotbar's socket, no numbers, and a trash slot that is one")

	var theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	check("the UI theme loads", theme != null)
	if theme == null:
		return
	var socket: StyleBoxTexture = theme.get_stylebox("panel", &"PanelSocket") as StyleBoxTexture
	check("the theme names the socket as PanelSocket",
		socket != null and socket.texture != null)
	if socket == null or socket.texture == null:
		return
	check("and it is the hotbar's slot art",
		socket.texture.resource_path == "res://art/images/hotbarslot.png",
		socket.texture.resource_path)

	# THE TWO COPIES AGREE.
	var hotbar_socket: StyleBoxTexture = _node_prop_in_scene("res://scene/ui/hotbar.tscn",
		"margin/slots/slot1", "theme_override_styles/panel") as StyleBoxTexture
	check("the hotbar's own socket is readable", hotbar_socket != null)
	if hotbar_socket != null:
		var drift: Array[String] = []
		if hotbar_socket.texture == null or \
				hotbar_socket.texture.resource_path != socket.texture.resource_path:
			drift.append("texture")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			if hotbar_socket.get_texture_margin(side) != socket.get_texture_margin(side):
				drift.append("texture margin %d" % side)
			if hotbar_socket.get_content_margin(side) != socket.get_content_margin(side):
				drift.append("content margin %d" % side)
		check("the inventory's socket and the hotbar's are the same socket",
			drift.is_empty(), "differ in: " + ", ".join(drift))

	# THE SLOT, AS IT ACTUALLY RESOLVES.
	var slot_scene: PackedScene = load("res://scene/ui/inventory/inventoryslot.tscn") as PackedScene
	check("inventoryslot.tscn loads", slot_scene != null and slot_scene.can_instantiate())
	if slot_scene != null and slot_scene.can_instantiate():
		var slot: Control = slot_scene.instantiate() as Control
		slot.theme = theme
		add_child(slot)
		var worn: StyleBoxTexture = slot.get_theme_stylebox("panel") as StyleBoxTexture
		check("an inventory slot wears the socket",
			worn != null and worn.texture != null
				and worn.texture.resource_path == "res://art/images/hotbarslot.png",
			worn)
		check("and carries no key number - that is the hotbar's keylabel, not the art",
			slot.find_child("keylabel", true, false) == null)
		slot.queue_free()

	# ONE SLOT SCENE FOR EVERY GRID. A scene that points its container at a slot
	# scene of its own quietly stops matching the others.
	var own_slots: Array[String] = []
	for path in ["res://scene/ui/inventory/inventory.tscn", "res://scene/ui/bank/bankinventory.tscn",
			"res://scene/ui/lootbag/lootbaginventory.tscn", "res://scene/ui/cooking/cookingscreen.tscn"]:
		if FileAccess.get_file_as_string(path).contains("inventory_slot_scene"):
			own_slots.append(path.get_file())
	check("the inventory, bank, loot bag and cooking grids all use the one slot",
		own_slots.is_empty(), "overridden in: " + ", ".join(own_slots))

	# THE GEAR SQUARES (day 1, "now the gear slots"). equipmentslot.tscn wears
	# the socket itself; the eight squares on the doll each used to override it
	# with the flat PanelSlot. Read as each square resolves, so an override left
	# on one square is caught by name.
	var gear: Node = (load("res://scene/ui/equipment/equipmentpanel.tscn") as PackedScene).instantiate()
	var flat_squares: Array[String] = []
	for square_name in ["helm", "chest", "legs", "boots", "weapon", "shield", "amulet", "ring"]:
		var square: Control = gear.find_child(square_name, true, false) as Control
		var face: StyleBoxTexture = null
		if square is EquipmentSlot:
			face = theme.get_stylebox("panel", square.theme_type_variation) as StyleBoxTexture
		if face == null or face.texture != socket.texture:
			flat_squares.append(square_name)
	gear.free()
	check("the eight gear squares wear the hotbar's socket too",
		flat_squares.is_empty(), "not a socket: " + ", ".join(flat_squares))

	# THE TRASH, IN BOTH PLACES.
	for path in ["res://scene/ui/inventory/inventory.tscn", "res://scene/ui/bank/bankinventory.tscn"]:
		var where: String = path.get_file()
		var trash_path: String = "mainpanel/margincontainer/vboxcontainer/trashrow/trashslot"
		var node_type: String = str(_node_type_in_scene(path, trash_path))
		check("%s has a trash slot" % where, node_type == "PanelContainer", node_type)
		check("%s's trash wears the socket" % where,
			str(_node_prop_in_scene(path, trash_path, "theme_type_variation")) == "PanelSocket")
		var script: Script = _node_prop_in_scene(path, trash_path, "script") as Script
		check("%s's trash runs trashslot.gd" % where,
			script != null and script.resource_path == "res://src/ui/inventory/trashslot.gd")
		check("%s's trash asks before it destroys anything" % where,
			str(_node_type_in_scene(path, trash_path + "/confirmationdialog")) == "ConfirmationDialog")
		for child in ["/centercontainer", "/centercontainer/icon"]:
			# NULL-SAFE ON PURPOSE: with the trash node missing entirely there
			# is no filter to read, and int(null) would unwind the rest of the
			# section - the glow checks below included - while the run still
			# printed 0 failed. Every check here fails by name instead.
			var filter: Variant = _node_prop_or_default(path, trash_path + child, "mouse_filter")
			check("%s: the trash's %s lets the drop through" % [where, child.get_file()],
				filter != null and int(filter) == Control.MOUSE_FILTER_IGNORE,
				"a child left on its default filter swallows the drag and the trash accepts nothing")

	# THE GLOW, AS BEHAVIOUR.
	var trash: PanelContainer = PanelContainer.new()
	trash.theme = theme
	trash.theme_type_variation = &"PanelSocket"
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.name = "confirmationdialog"
	trash.add_child(dialog)
	trash.set_script(load("res://src/ui/inventory/trashslot.gd"))
	add_child(trash)
	check("the trash probe is in the tree, so _ready() ran", trash.is_inside_tree())
	check("it rests unlit", not trash.is_hot())
	var idle_style: StyleBox = trash.get_theme_stylebox("panel")

	var from_bag: Dictionary = {"stack": null, "source_slot": null, "source_type": "inventory"}
	check("it accepts an item dragged from the bag", trash._can_drop_data(Vector2.ZERO, from_bag))
	check("AND GLOWS WHILE IT IS OVER IT", trash.is_hot())
	var hot_style: StyleBoxTexture = trash.get_theme_stylebox("panel") as StyleBoxTexture
	check("the glow is really a different look, not the same socket",
		hot_style != null and idle_style != hot_style and hot_style.modulate_color != Color.WHITE,
		hot_style.modulate_color if hot_style != null else null)

	trash.notification(Control.NOTIFICATION_DRAG_END)
	check("and goes out when the drag ends", not trash.is_hot())

	# A SECOND DROP WHILE ONE IS BEING CONFIRMED is the drag it refuses now.
	# It used to refuse every hotbar drag too, back when a key only pointed at
	# a bag item; see _test_the_hotbar_holds_items() for the key it accepts.
	trash.confirm_dialog.visible = true
	check("it refuses a second drop while a delete is being confirmed",
		not trash._can_drop_data(Vector2.ZERO, from_bag))
	check("and does not glow for something it will refuse", not trash.is_hot(),
		"a target that lights up and then says no is worse than one that never lit")
	trash.confirm_dialog.visible = false

	trash._can_drop_data(Vector2.ZERO, from_bag)
	trash.notification(Control.NOTIFICATION_MOUSE_EXIT)
	check("and goes out when you drag away from it", not trash.is_hot())
	trash.queue_free()

	print("  one socket for every slot, and a trash slot in the bag and the bank")


func _node_prop_in_scene(path: String, node_path: String, prop: String) -> Variant:
	"""A node's property, read out of a PackedScene without instancing it."""
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var state: SceneState = packed.get_state()
	for i in range(state.get_node_count()):
		if str(state.get_node_path(i)) != "./" + node_path and str(state.get_node_path(i)) != node_path:
			continue
		for p in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, p) == prop:
				return state.get_node_property_value(i, p)
		return null
	return null


func _node_type_in_scene(path: String, node_path: String) -> Variant:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var state: SceneState = packed.get_state()
	for i in range(state.get_node_count()):
		if str(state.get_node_path(i)) == "./" + node_path or str(state.get_node_path(i)) == node_path:
			return state.get_node_type(i)
	return null

func _node_prop_or_default(path: String, node_path: String, prop: String) -> Variant:
	"""Like _node_prop_in_scene(), but an absent property is its CLASS DEFAULT.

	A .tscn omits any property left at its default, so "not in the file" means
	"the default", never "unknown". The first version of the trash checks read
	the raw value and passed it to int() - and when the sabotage removed
	`mouse_filter = 2`, the property was absent, the value was null, int(null)
	raised, and GDScript unwound THE REST OF THE SECTION. Sixteen checks
	vanished and the run still said 0 failed. That is the trap CLAUDE.md
	describes under "a runtime error inside a section aborts it", found by the
	sabotage meant to test something else.

	The default comes from ClassDB rather than from a number typed in here, so
	it is the engine's answer for that node's actual class."""
	var value: Variant = _node_prop_in_scene(path, node_path, prop)
	if value != null:
		return value
	var node_type: String = str(_node_type_in_scene(path, node_path))
	if node_type == "" or not ClassDB.class_exists(node_type):
		return null
	return ClassDB.class_get_property_default_value(node_type, prop)


# =============================================================================
# THE BANK
# =============================================================================
# Four things held the bank back, measured off a screenshot of it in play:
#
#   - THE BALANCE WAS THE SMALLEST TEXT ON THE PANEL. 12pt "Bank Gold: 0" with a
#     16px coin, under a full-width empty input. The number you open the bank
#     to read is now 16pt with a 24px coin, and what you are CARRYING sits beside
#     it - deposit and withdraw move gold between those two piles, and only one
#     of them used to be on screen.
#   - THE BUTTONS FLOATED, centred under the box, a row away from the amount
#     they act on. They share a row with it now, and the field says what it is
#     for: "Gold amount", asked for once the buttons moved beside it.
#   - THE GRID WAS CUT MID-ROW at the bottom, which read as broken. The bank is
#     fifty slots - five rows - so it no longer scrolls at all: the scroll area
#     is sized by the grid, and a partial row cannot exist.
#   - THE BOXES WERE TOO FAR APART. The socket art carries 4px of transparent
#     border on every side, so two sockets at separation 4 had 12px of empty
#     space between them. Separation -4 overlaps exactly the transparent part
#     and leaves a 4px gap; the check derives that 4 from the art's own alpha,
#     so a redrawn socket fails here rather than overlapping visible pixels.
#
# Plus BANK in capitals to match INVENTORY, and a themed scrollbar - global, so
# every list in the game now matches rather than the bank alone.
#
# THE SCRIPT REACHES ITS CONTROLS BY %UNIQUE NAME NOW, and that is the check
# that matters most. It used five-level $paths "matching the scene structure";
# rebuilding the gold area would have turned all four into null at runtime,
# which does not fail to compile - it is a Deposit button that does nothing.

func _test_the_bank_reads_well() -> void:
	section("BANK — the balance you came for, beside what moves it")

	var scene_path: String = "res://scene/ui/bank/bankinventory.tscn"
	var script_path: String = "res://src/ui/bank/bankinventory.gd"
	var VB: String = "mainpanel/margincontainer/vboxcontainer"

	check("the header says BANK, matching INVENTORY",
		str(_node_prop_in_scene(scene_path, VB + "/headerpanel/hboxcontainer/headerlabel", "text")) == "BANK"
			and str(_node_prop_in_scene("res://scene/ui/inventory/inventory.tscn",
				VB + "/headerpanel/hboxcontainer/headerlabel", "text")) == "INVENTORY")

	# LAYOUT, BY PARENTAGE.
	var balance: String = VB + "/currencypanel/currencyvbox/goldcontainer"
	var actions: String = VB + "/currencypanel/currencyvbox/actionrow"
	for pair in [[balance, "goldicon"], [balance, "goldlabel"], [balance, "carrylabel"],
			[actions, "goldinput"], [actions, "depositbuttons"], [actions, "withdrawbutton"]]:
		check("%s sits in the %s row" % [pair[1], "balance" if pair[0] == balance else "action"],
			_node_type_in_scene(scene_path, pair[0] + "/" + pair[1]) != null)
	var placeholder: String = str(_node_prop_in_scene(scene_path, actions + "/goldinput", "placeholder_text"))
	check("the amount field says it is gold", placeholder.to_lower().contains("gold"),
		"'%s' - beside Deposit AND Withdraw, 'Enter amount' does not say of what" % placeholder)
	var icon_size: Variant = _node_prop_in_scene(scene_path, balance + "/goldicon", "custom_minimum_size")
	check("the coin is big enough to read", icon_size is Vector2 and (icon_size as Vector2).y >= 24.0, icon_size)

	# EVERY %NAME THE SCRIPT USES IS A UNIQUE NODE IN THE SCENE.
	var src: String = _code_only(FileAccess.get_file_as_string(script_path))
	var packed: PackedScene = load(scene_path) as PackedScene
	var unique_names: Dictionary = {}
	if packed != null:
		var state: SceneState = packed.get_state()
		for i in range(state.get_node_count()):
			for p in range(state.get_node_property_count(i)):
				if state.get_node_property_name(i, p) == "unique_name_in_owner" \
						and bool(state.get_node_property_value(i, p)):
					unique_names[str(state.get_node_name(i))] = true
	# ONLY THE SCRIPT'S OWN LOOKUPS. The first version matched every "%word" in
	# the file, and reported "%d" and "%s" - format specifiers, `"%s in bank" %
	# ...` - plus `inv_screen.get_node_or_null("%inventorycontainer")`, which is
	# a unique name in a DIFFERENT scene, resolved on a different node. Two
	# shapes are this node's own: `= %name`, and get_node[_or_null]("%name")
	# called with no receiver in front of it.
	var used: Dictionary = {}
	var direct := RegEx.new()
	direct.compile("=\\s*%([a-z_][a-z0-9_]*)")
	var by_call := RegEx.new()
	by_call.compile("(?<![.\\w])get_node(?:_or_null)?\\(\\s*\"%([a-z_][a-z0-9_]*)\"")
	for rx in [direct, by_call]:
		for m in rx.search_all(src):
			used[m.get_string(1)] = true
	var dangling: Array[String] = []
	for name_used in used:
		if not unique_names.has(name_used):
			dangling.append("%" + name_used)
	check("the script found some %names to check", used.size() >= 5, used.keys())
	check("every %name bankinventory.gd reaches exists, and is unique, in the scene",
		dangling.is_empty(), "missing or not unique: " + ", ".join(dangling))
	check("and the gold controls are reached by name, not by a path that can move",
		not src.contains("$mainpanel/margincontainer/vboxcontainer/currencypanel")
			and not src.contains("goldbuttons/"))

	# BOTH PILES ARE WRITTEN.
	var upd: int = _first_code_index(src, "func _update_gold_ui(", 0)
	var upd_end: int = _first_code_index(src, "\nfunc ", upd + 1)
	check("refreshing the gold writes what you carry as well as what is banked",
		upd != -1 and _within(_first_code_index(src, "carry_label.text", upd), upd_end) != -1
			and _within(_first_code_index(src, "gold_label.text", upd), upd_end) != -1)

	# THE GRID: NO SCROLL, NO PARTIAL ROW.
	# THE INVENTORY TOO. Asked for next ("space inventory closer also"), and the
	# two are open side by side whenever you bank, so they are held to the same
	# rule in the same place. Its old fixed 200px scroll height would have left
	# a 20px empty band under a grid that is 180px at the new spacing.
	var grids: Array = [
		["the bank", scene_path, VB + "/bankscroll", VB + "/bankscroll/bankcontainer"],
		["the inventory", "res://scene/ui/inventory/inventory.tscn", VB + "/inventoryscroll",
			VB + "/inventoryscroll/scrollcontent/inventorycontainer"],
	]
	for g in grids:
		check("%s no longer scrolls vertically" % g[0],
			int(_node_prop_or_default(g[1], g[2], "vertical_scroll_mode")) \
				== ScrollContainer.SCROLL_MODE_DISABLED)
	var probe_scroll := ScrollContainer.new()
	probe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var probe_grid := GridContainer.new()
	probe_grid.columns = 10
	probe_grid.add_theme_constant_override("h_separation", -4)
	probe_grid.add_theme_constant_override("v_separation", -4)
	for _i in range(50):
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(48, 48)
		probe_grid.add_child(cell)
	probe_scroll.add_child(probe_grid)
	add_child(probe_scroll)
	# AT LEAST THE GRID, NOT EXACTLY IT. The first version asserted equality and
	# measured 232 against 224: the ScrollContainer adds its own panel's content
	# margins on top of the child. More than the grid is exactly what "no partial
	# row" needs, so that is the claim.
	var grid_h: float = probe_grid.get_combined_minimum_size().y
	check("five rows of 48px at -4 separation are 224px of grid",
		grid_h == 5 * 48 - 4 * 4, grid_h)
	check("and a ScrollContainer that does not scroll grows to hold all of it",
		probe_scroll.get_combined_minimum_size().y >= grid_h,
		"%s for a %s grid - the engine behaviour this layout rests on" % [
			probe_scroll.get_combined_minimum_size().y, grid_h])
	probe_scroll.queue_free()

	# THE BOXES: -4, BECAUSE THE ART'S TRANSPARENT BORDER IS 4.
	var art: Image = (load("res://art/images/hotbarslot.png") as Texture2D).get_image()
	var used_rect: Rect2i = art.get_used_rect()
	var padding: int = used_rect.position.x
	check("the socket art's transparent border is the same on all four sides",
		used_rect.position.x == used_rect.position.y
			and art.get_width() - used_rect.end.x == padding
			and art.get_height() - used_rect.end.y == padding, used_rect)
	for g in grids:
		var hsep: Variant = _node_prop_in_scene(g[1], g[3], "theme_override_constants/h_separation")
		var vsep: Variant = _node_prop_in_scene(g[1], g[3], "theme_override_constants/v_separation")
		check("%s's boxes sit closer - overlapping only the art's transparent border" % g[0],
			hsep != null and vsep != null and int(hsep) == -padding and int(vsep) == -padding,
			"separation (%s, %s), border %d - any further and one socket covers the next" % [hsep, vsep, padding])

	# AND THE HOTBAR, asked for last ("make hotbar closer"). Same socket art, so
	# the same number - but an HBoxContainer spells it `separation`, not
	# h_/v_separation, so it gets its own line rather than a row in the loop.
	var bar_sep: Variant = _node_prop_in_scene("res://scene/ui/hotbar.tscn", "margin/slots",
		"theme_override_constants/separation")
	check("the hotbar's boxes sit closer too, by the same border",
		bar_sep != null and int(bar_sep) == -padding,
		"separation %s, border %d - the hotbar and the bag should read as one set of slots" % [bar_sep, padding])

	# THE SCROLLBAR, EVERYWHERE.
	var theme: Theme = load("res://assets/themes/rpg_ui_theme.tres") as Theme
	check("scrollbars are themed, not Godot's default grey",
		theme != null and theme.has_stylebox("grabber", &"VScrollBar")
			and theme.has_stylebox("scroll", &"VScrollBar"))

	print("  balance and carry side by side, the buttons by their field, the whole grid on show")


# =============================================================================
# THE GM PANEL IS A WINDOW, AND SAYS WHAT IT DID
# =============================================================================
# Asked for as "gm panel needs a x button to close - can you improve this also",
# and then all four of: results in the panel, drag/resize/stay put, tidy the
# look, tabs instead of scrolling.
#
# THE ONE THAT MATTERED MOST WAS NOT ON SCREEN. Every result - View account, a
# kick, a ban, a rank change, closing the server - went through _say(), which
# printed to the Output console and nowhere else, and only in a debug build. In
# an exported game the panel for acting on other people never said what it had
# done. Everything lands in a results box now.
#
# Instanced for real: its _ready() asks /api/status, which fails quietly with
# no server here, and nothing below depends on the answer.

func _test_the_gm_panel_is_a_window() -> void:
	section("GM PANEL — an x, a window, three tabs, and results on screen")

	var packed: PackedScene = load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene
	check("ownerpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame

	# ---- a window ----
	check("it is attached as a window, so it drags, resizes and remembers",
		panel.get("_window") != null)

	# ---- the x ----
	var close: Button = panel.get_node_or_null("%ownerclosebutton") as Button
	var header: Node = panel.get_node_or_null("frame/margin/rows/headerpanel")
	check("there is an x", close != null)
	check("and it sits in the header, where every other panel keeps its x",
		close != null and header != null and header.is_ancestor_of(close))
	if close != null:
		close.pressed.emit()
	check("pressing it closes the panel", not panel.visible)
	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var hide_at: int = _first_code_index(hud_src, "func hide_panel(", 0)
	var hide_end: int = _first_code_index(hud_src, "\nfunc ", hide_at + 1)
	check("and Esc closes it too, with the rest",
		_within(_first_code_index(hud_src, "owner_panel.close()", hide_at), hide_end) != -1)
	panel.visible = true
	await get_tree().process_frame

	# ---- every node the script reads is in the scene ----
	var script_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/owner/ownerpanel.gd"))
	# THE TWO WAYS THIS SCRIPT NAMES A NODE: `= %name` and get_node_or_null(
	# "%name"). A bare %name pattern also matches every "%s" and "%d" in the
	# file's format strings, which is noise, not evidence.
	var unique := RegEx.new()
	unique.compile("(?:= %|get_node(?:_or_null)?\\(\"%)([a-z][a-z0-9_]+)")
	var missing: Array[String] = []
	var asked: int = 0
	for m in unique.search_all(script_src):
		var wanted: String = m.get_string(1)
		asked += 1
		if wanted == "inventorycontainer":
			continue  # the HUD's, not this panel's
		if panel.get_node_or_null("%" + wanted) == null:
			missing.append(wanted)
	check("every control the script asks for by name is in the scene",
		missing.is_empty() and asked >= 25, "missing, so silently skipped: %s (%d asked)" % [missing, asked])

	# ---- three tabs, no scrolling ----
	var tabs: TabContainer = panel.get_node_or_null("%ownertabs") as TabContainer
	check("the sections are tabs", tabs != null)
	if tabs == null:
		panel.queue_free()
		return
	var titles: Array[String] = []
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	check("Account, Testing and Server", titles == ["Account", "Testing", "Server"], titles)
	check("sized to the tallest tab, so switching never resizes the window",
		tabs.use_hidden_tabs_for_min_size)
	# OWNED ONLY: an OptionButton's popup carries a ScrollContainer of its own,
	# which is the engine's and not this scene's.
	var scrollers: Array = panel.find_children("*", "ScrollContainer", true, true)
	check("and nothing in it scrolls", scrollers.is_empty(),
		"%d ScrollContainer(s)" % scrollers.size())

	var mins: Array[float] = []
	var cut: Array[String] = []
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await get_tree().process_frame
		mins.append(PanelWindow.content_minimum(panel).y)
		# A HINT THAT IS CUT OFF is not a hint. Measured with the box's own
		# font, size and padding, on the tab that is actually showing.
		for edit in tabs.get_current_tab_control().find_children("*", "LineEdit", true, true):
			var line: LineEdit = edit as LineEdit
			if line.placeholder_text == "" or not line.is_visible_in_tree():
				continue
			var font: Font = line.get_theme_font("font")
			var fsize: int = line.get_theme_font_size("font_size")
			var box: StyleBox = line.get_theme_stylebox("normal")
			var room: float = line.size.x - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0)
			var need: float = font.get_string_size(line.placeholder_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			if need > room:
				cut.append("%s: '%s' needs %d, has %d" % [line.name, line.placeholder_text, need, room])
	check("the window is the same height on every tab", mins.max() == mins.min(), mins)
	check("no input's hint is cut off", cut.is_empty(), cut)
	tabs.current_tab = 0

	# THE AUTHORED RECTANGLE ALREADY HOLDS THE TALLEST TAB, so the panel opens at
	# its drawn size rather than being grown by PanelWindow on first show - and
	# it clears the menu bar along the bottom of a 1280x720 screen.
	# READ FROM THE SCENE, not the live node: PanelWindow may have restored a
	# rectangle saved by an earlier run, and that is not what a new player gets.
	var need_h: float = PanelWindow.content_minimum(panel).y
	var top: float = 0.0
	var bottom: float = 0.0
	var root_state: SceneState = packed.get_state()
	for p in root_state.get_node_property_count(0):
		match root_state.get_node_property_name(0, p):
			"offset_top":
				top = float(root_state.get_node_property_value(0, p))
			"offset_bottom":
				bottom = float(root_state.get_node_property_value(0, p))
	var authored_h: float = bottom - top
	check("its default size holds its tallest tab",
		authored_h + 0.5 >= need_h, "authored %d, needs %d" % [authored_h, need_h])
	check("and it opens clear of the menu bar", bottom <= 720.0 - 76.0, bottom)

	# ---- tidy: no button left on the engine's default look ----
	# THE STYLE THE BUTTON ENDS UP WITH, not whether it carries an override.
	# Since day 1 the staff theme dresses them, and an override per button is
	# exactly what would stop a theme change reaching them.
	var engine_button: StyleBox = ThemeDB.get_default_theme().get_stylebox("normal", "Button")
	var plain: Array[String] = []
	for node in panel.find_children("*", "Button", true, true):
		if node is CheckButton or node is OptionButton:
			continue
		var worn: StyleBox = (node as Button).get_theme_stylebox("normal")
		if worn == null or worn == engine_button:
			plain.append(String(node.name))
	check("every button wears the panel's style", plain.is_empty(), plain)

	# ---- results on screen ----
	var results: RichTextLabel = panel.get_node_or_null("%ownerresults") as RichTextLabel
	check("there is a results box", results != null)
	if results != null:
		panel._say("[GM] signed 'probe' out of 2 place(s).", panel.SAY_GOOD)
		var shown: String = results.get_parsed_text()
		check("a result lands in the box", shown.contains("signed 'probe' out"), shown)
		check("without the console's tag", not shown.contains("[GM]"), shown)
		panel._say("[b]not bold[/b] from a username")
		check("and a name or an error is text, never markup",
			results.get_parsed_text().contains("[b]not bold[/b]"), results.get_parsed_text())
		# NOT ONLY IN A DEBUG BUILD. The suite always runs one, so a behavioural
		# check cannot see the guard that made the old panel silent in an export.
		# The write has to sit outside it, at the function's own indentation.
		var say_at: int = _first_code_index(script_src, "func _say(", 0)
		var say_end: int = _first_code_index(script_src, "\nfunc ", say_at + 1)
		check("and it is written in every build, not just a debug one",
			_within(_first_code_index(script_src, "\n\t_write(line, colour)", say_at), say_end) != -1)

		# THE QUICK ANSWERS TOO. The Testing tab and the teleport row had labels
		# of their own that grew the tab past its window whenever they spoke;
		# they write here now.
		panel._set_testing_status("Added 1 x probeitem to your bag.")
		panel._set_teleport_status("[GM] type a username first.")
		check("the Testing tab's answers land in the box too",
			results.get_parsed_text().contains("Added 1 x probeitem"))
		check("and so do the teleport row's",
			results.get_parsed_text().contains("type a username first."))
		panel._print_save_summary("probe", {"username": "probe", "role": "mod",
			"characters": [], "kills": []})
		shown = results.get_parsed_text()
		check("an account view appears in the box", shown.contains("rank      : mod"), shown)
		check("AFTER what was already there - a rank change's confirmation survives the view it triggers",
			shown.contains("signed 'probe' out") and shown.find("signed 'probe' out") < shown.find("rank      : mod"))
		var clear: Button = panel.get_node_or_null("%ownerresultsclear") as Button
		if clear != null:
			clear.pressed.emit()
		check("and Clear empties it", results.get_parsed_text().strip_edges() == "",
			results.get_parsed_text())

	panel.queue_free()
	await get_tree().process_frame
	print("  a window with an x, three tabs, and a results box instead of the console")


# =============================================================================
# NOTICES FADE, AND LOGGING IN IS QUIET
# =============================================================================
# Reported with a screenshot of five lines parked above the menu bar - "The
# server is open again", "Update in progress", "Everyone has been moved to
# elusion" twice - and "we need a way to hide this so it's not distracting".
#
# TWO DEFECTS MADE THAT PICTURE, and the comments described neither:
#
#   The box never faded. Every comment about it said it did; nothing did. A
#   line left only when a newer one pushed it off the top.
#
#   Logging in announced a week. The first poll asks since=0 and gets the
#   recent TAIL, and every entry in it popped the box as if it were news.
#
# And a third, found on the way: "the log always gets it" was only true once
# chat had been opened, because chat is built on first use. Before that a
# notice that faded was gone. So the fade could not be added without first
# making sure fading loses nothing.
#
# Driven on a bare HUD instance, never added to the tree - _ready() would start
# polling a server. _age_messages() takes its clock as an argument, so a line
# ages ten seconds without the suite waiting ten seconds.

func _test_notices_fade_and_login_is_quiet() -> void:
	section("NOTICES — the box fades, a login's backlog is not news, and nothing is lost")

	var hud_script: Script = load("res://src/ui/characterhud.gd") as Script
	check("characterhud.gd loads", hud_script != null and hud_script.can_instantiate())
	if hud_script == null or not hud_script.can_instantiate():
		return
	var hud: Object = hud_script.new()
	hud._build_message_box()
	var box: Control = hud.message_box
	var rows: Control = hud.message_rows
	check("the box starts hidden", box != null and not box.visible)
	if box == null or rows == null:
		hud.free()
		return

	var show_ms: int = int(hud_script.MESSAGE_SHOW_SECONDS * 1000.0)
	var fade_ms: int = int(hud_script.MESSAGE_FADE_SECONDS * 1000.0)
	check("a notice stays up long enough to read and not much longer",
		show_ms >= 5000 and show_ms <= 15000 and fade_ms > 0, [show_ms, fade_ms])

	# ---- it fades ----
	hud._push_message("The server is open again.", Color.WHITE)
	check("a live notice pops the box", rows.get_child_count() == 1 and box.visible)
	# A PLACEHOLDER when nothing was pushed, so a broken push fails the checks
	# below by name instead of unwinding the section on a null.
	var line: Control = rows.get_child(0) as Control if rows.get_child_count() > 0 else Control.new()
	var shown: int = int(line.get_meta("shown_msec", -1))
	check("and is stamped with when it went up", shown >= 0, shown)

	hud._age_messages(shown + show_ms - 1)
	check("it is fully there until its time is up",
		rows.get_child_count() == 1 and is_equal_approx(line.modulate.a, 1.0) and box.visible)
	hud._age_messages(shown + show_ms + fade_ms / 2)
	check("then it fades", line.modulate.a > 0.2 and line.modulate.a < 0.8, line.modulate.a)
	hud._age_messages(shown + show_ms + fade_ms + 1)
	check("THEN IT IS GONE", rows.get_child_count() == 0, rows.get_child_count())
	check("and an empty box hides itself", not box.visible)

	# EACH LINE ON ITS OWN CLOCK, not the box's. A notice that arrived five
	# seconds after another must not vanish with it.
	for leftover in rows.get_children():
		rows.remove_child(leftover)
		leftover.queue_free()
	hud._push_message("first", Color.WHITE)
	hud._push_message("second", Color.WHITE)
	if rows.get_child_count() == 2:
		var first: Control = rows.get_child(0) as Control
		var second: Control = rows.get_child(1) as Control
		second.set_meta("shown_msec", int(first.get_meta("shown_msec")) + 5000)
		hud._age_messages(int(first.get_meta("shown_msec")) + show_ms + fade_ms + 1)
		check("each line fades on its own clock",
			rows.get_child_count() == 1 and rows.get_child(0) == second and box.visible,
			rows.get_child_count())
		hud._age_messages(int(second.get_meta("shown_msec")) + show_ms + fade_ms + 1)
	else:
		check("each line fades on its own clock", false,
			"two pushes left %d lines" % rows.get_child_count())
	for leftover in rows.get_children():
		rows.remove_child(leftover)
		leftover.queue_free()

	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var proc: int = _first_code_index(hud_src, "func _process(", 0)
	var guard: int = _first_code_index(hud_src, "if active_character == null:", proc)
	var ages: int = _first_code_index(hud_src, "_age_messages(", proc)
	check("the HUD ages the box every frame, before the no-character guard",
		ages != -1 and guard != -1 and ages < guard,
		"age %d, guard %d - below the guard, a notice in a menu never fades" % [ages, guard])

	# ---- a login's backlog is history ----
	var before: int = hud._unlogged_lines.size()
	hud._read_broadcast_messages([
		{"body": "Update in progress - please come back later.", "kind": "system", "at": 1700000000},
		{"body": "Everyone has been moved to elusion.", "kind": "system", "at": 1700000100},
		{"body": "The server is open again.", "kind": "system", "at": 1700000200},
	], false)
	check("the catch-up does not pop the box", rows.get_child_count() == 0 and not box.visible,
		rows.get_child_count())
	check("BUT IT IS STILL RECORDED, every line of it",
		hud._unlogged_lines.size() == before + 3, hud._unlogged_lines.size() - before)
	# NULL-SAFE, and the sabotage that drops the buffer is why: indexing an
	# empty list raised, unwound the rest of this section, and the run lost
	# fifteen checks while reporting one red. Each read below is guarded.
	var said: Variant = hud._unlogged_lines[before] if hud._unlogged_lines.size() > before else null
	check("with the time it was said, not the time it was read",
		said is Dictionary and int(said["at"]) == 1700000000, said)
	hud._read_broadcast_messages([{"body": "Tunacan has gone hostile.", "kind": "system",
		"at": 1700000300}], true)
	check("while a notice arriving after that is announced", rows.get_child_count() == 1)

	# THE POLL'S ANSWER, DRIVEN. These two were read off the source while the
	# handling sat inside the request; _apply_broadcast() is the handling on its
	# own now, so they are what happens rather than what is written.
	for leftover in rows.get_children():
		rows.remove_child(leftover)
		leftover.queue_free()
	hud._broadcast_cursor = 0
	hud._apply_broadcast({"latest_id": 40, "messages": [
		{"body": "A week-old restart notice.", "kind": "system", "at": 1700000400}]})
	check("the poll announces only once it has caught up - cursor past 0",
		rows.get_child_count() == 0, "a poll from cursor 0 is answered with a week of notices")
	check("and asks BEFORE it moves the cursor, or the first answer counts as caught up",
		hud._broadcast_cursor == 40, hud._broadcast_cursor)
	hud._apply_broadcast({"latest_id": 41, "messages": [
		{"body": "Tunacan has gone hostile.", "kind": "system", "at": 1700000500}]})
	check("and the next answer, arriving after, is news", rows.get_child_count() == 1
		and hud._broadcast_cursor == 41, rows.get_child_count())
	var poll: int = _first_code_index(hud_src, "func _on_broadcast_poll_timeout(", 0)
	var poll_end: int = _first_code_index(hud_src, "\nfunc ", poll + 1)
	check("and the poll hands its answer to _apply_broadcast()",
		_within(_first_code_index(hud_src, "_apply_broadcast(data)", poll), poll_end) != -1)

	# ---- nothing is lost before chat exists ----
	var client_line_at: int = int(Time.get_unix_time_from_system())
	hud._push_message("Lost connection.", Color.RED)
	var last: Variant = hud._unlogged_lines.back() if not hud._unlogged_lines.is_empty() else null
	check("a notice this client made itself is stamped now, not at the flush",
		last is Dictionary and int(last["at"]) >= client_line_at, last)

	var stub_script := GDScript.new()
	stub_script.source_code = "extends Control\nvar got: Array = []\n" \
		+ "func push_system_line(text: String, _c: Color, at: int = 0) -> void:\n" \
		+ "\tgot.append([text, at])\n"
	stub_script.reload()
	var chat: Control = Control.new()
	chat.set_script(stub_script)
	chat.visible = false
	var waiting: int = hud._unlogged_lines.size()
	hud.chat_panel = chat
	hud._flush_unlogged_lines()
	check("when chat is built, everything that waited is written into it",
		chat.got.size() == waiting, [chat.got.size(), waiting])
	check("in order, with the server's own time",
		chat.got.size() > before and chat.got[before] == ["Update in progress - please come back later.", 1700000000],
		chat.got.slice(before, before + 1))
	check("and none of it is written twice", hud._unlogged_lines.is_empty(),
		hud._unlogged_lines.size())
	var toggle: int = _first_code_index(hud_src, "func toggle_chat(", 0)
	var built: int = _first_code_index(hud_src, "add_child(chat_panel)", toggle)
	var flushed: int = _first_code_index(hud_src, "_flush_unlogged_lines()", toggle)
	check("and toggle_chat() flushes as it builds chat",
		built != -1 and flushed != -1 and flushed > built
			and _within(flushed, _first_code_index(hud_src, "\nfunc ", toggle + 1)) != -1,
		[built, flushed])

	# ---- with chat there ----
	var got_before: int = chat.got.size()
	var rows_before: int = rows.get_child_count()
	hud._push_message("hidden chat", Color.WHITE)
	check("with chat built but closed, a notice is logged AND announced",
		chat.got.size() == got_before + 1 and rows.get_child_count() == rows_before + 1,
		[chat.got.size() - got_before, rows.get_child_count() - rows_before])
	chat.visible = true
	rows_before = rows.get_child_count()
	hud._push_message("open chat", Color.WHITE)
	check("with chat open, it is logged and not announced twice",
		chat.got.size() == got_before + 2 and rows.get_child_count() == rows_before)
	hud._age_messages(Time.get_ticks_msec())
	check("and the box stands down while chat is up, even with lines in it",
		rows.get_child_count() > 0 and not box.visible)
	chat.visible = false
	hud._age_messages(Time.get_ticks_msec())
	check("and comes back when chat closes, if anything is still fresh", box.visible)

	# ---- the waiting list is bounded ----
	hud.chat_panel = null
	for i in 60:
		hud._push_message("notice %d" % i, Color.WHITE, 0, false)
	check("notices waiting for chat are capped",
		hud._unlogged_lines.size() == hud_script.UNLOGGED_KEPT, hud._unlogged_lines.size())
	var oldest: Variant = hud._unlogged_lines[0] if not hud._unlogged_lines.is_empty() else null
	check("oldest dropped first",
		oldest is Dictionary and str(oldest["text"]) == "notice %d" % (60 - hud_script.UNLOGGED_KEPT),
		oldest)

	chat.free()
	hud.free()
	print("  %.0fs up, %.1fs to fade; a login's backlog goes to the log, not the screen"
		% [hud_script.MESSAGE_SHOW_SECONDS, hud_script.MESSAGE_FADE_SECONDS])


# =============================================================================
# THE HOTBAR HOLDS ITEMS
# =============================================================================
# Asked for as "make items travel instead of staying on one screen - we built
# an equipment screen to solve this problem". The keys used to hold an item_id
# pointing into the bag, so a potion showed in its bag cell AND on its key.
# Now each key holds the stack itself, as the backpack's cells 20-29, and
# dragging one onto a key moves it the way equipping moves a piece.
#
# The keys are ten (1-9 then 0), and that part is unchanged from the section
# this replaces: the counts, the key mapping, a real key press, and the frame
# hugging the slots are all still checked below.
#
# BEHAVIOURAL, WITH A REAL CONTAINER AND A REAL BAR. The items are two
# synthetic ItemData registered for the duration and removed after, so none of
# this needs the private art pack - it ran as a skip-shaped hole before.

const _HB_POTION := "zz_hotbar_test_potion"
const _HB_SWORD := "zz_hotbar_test_sword"


func _hb_cells(cells: Dictionary, length: int) -> Array:
	# A positional save array of `length`, {position: [item_id, qty]}.
	var out: Array = []
	out.resize(length)
	for position in cells:
		out[position] = {"item_id": cells[position][0], "quantity": cells[position][1]}
	return out


func _hb_holds(slot: InventorySlot, item_id: String, quantity: int) -> bool:
	return slot != null and not slot.is_empty() \
		and slot.stack.data.item_id == item_id and slot.stack.quantity == quantity


func _hb_drag(from: InventorySlot) -> Dictionary:
	# The drag data InventorySlot._get_drag_data() builds, without starting a
	# real drag - set_drag_preview() needs one in progress.
	return {"stack": from.stack.duplicate_stack(), "source_slot": from,
		"source_type": from.slot_type}


func _test_the_hotbar_holds_items() -> void:
	section("HOTBAR — ten keys that hold their items, 1-9 then 0")

	# ---- ten keys ----
	check("the hotbar is ten keys", Hotbar.SLOT_COUNT == 10, Hotbar.SLOT_COUNT)
	check("there is one key per slot",
		Hotbar.SLOT_KEYS.size() == Hotbar.SLOT_COUNT, Hotbar.SLOT_KEYS.size())
	var distinct: Dictionary = {}
	for k in Hotbar.SLOT_KEYS:
		distinct[k] = true
	check("and no key fires two slots",
		distinct.size() == Hotbar.SLOT_KEYS.size(), Hotbar.SLOT_KEYS)
	var misrouted: Array = []
	for i in Hotbar.SLOT_KEYS.size():
		if Hotbar.slot_for_key(Hotbar.SLOT_KEYS[i]) != i:
			misrouted.append("%s -> %d" % [OS.get_keycode_string(Hotbar.SLOT_KEYS[i]),
				Hotbar.slot_for_key(Hotbar.SLOT_KEYS[i])])
	check("every key fires its own slot", misrouted.is_empty(), misrouted)
	# BY NAME, because 0 is the one that arithmetic gets wrong: KEY_0 sits one
	# BELOW KEY_1, so `keycode - KEY_1` sends it to slot -1.
	check("0 fires the tenth slot", Hotbar.slot_for_key(KEY_0) == 9,
		Hotbar.slot_for_key(KEY_0))
	check("a letter fires nothing", Hotbar.slot_for_key(KEY_Q) == -1,
		Hotbar.slot_for_key(KEY_Q))

	# ---- fixtures ----
	var potion := ItemData.new()
	potion.item_id = _HB_POTION
	potion.display_name = "Test Potion"
	potion.stackable = true
	potion.max_stack = 20
	var sword := ItemData.new()
	sword.item_id = _HB_SWORD
	sword.display_name = "Test Sword"
	ItemRegistry._items[_HB_POTION] = potion
	ItemRegistry._items[_HB_SWORD] = sword

	var packed: PackedScene = load("res://scene/ui/hotbar.tscn") as PackedScene
	check("hotbar.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		ItemRegistry._items.erase(_HB_POTION)
		ItemRegistry._items.erase(_HB_SWORD)
		return
	var bar: Hotbar = packed.instantiate() as Hotbar
	var bag := InventoryContainer.new()
	add_child(bag)
	add_child(bar)
	await get_tree().process_frame

	var grid: int = bag.capacity
	var carry: int = grid + Hotbar.SLOT_COUNT
	check("the bag's grid is the server's twenty", grid == 20, grid)

	# COUNTED, NOT LOOKED UP BY NAME. A lookup of slot1..slot<SLOT_COUNT> passes
	# on a scene with an eleventh slot nobody can fire.
	var row: Node = bar.get_node_or_null("margin/slots")
	var drawn: int = 0
	if row != null:
		for child in row.get_children():
			if child is HotbarSlot:
				drawn += 1
	check("the bar draws exactly SLOT_COUNT keys", drawn == Hotbar.SLOT_COUNT,
		"%d drawn, %d keys" % [drawn, Hotbar.SLOT_COUNT])
	check("and resolves every one of them",
		bar.slots.size() == Hotbar.SLOT_COUNT and not bar.slots.has(null), bar.slots)

	# ---- the keys arrive with the bag, even before the bar is attached ----
	# The HUD loads the bag and THEN wires the hotbar. Cells 20-29 in that first
	# load must be kept, not dropped for want of a slot to put them in.
	bag.load_save_array(_hb_cells({3: [_HB_SWORD, 1], grid + 1: [_HB_POTION, 5]}, carry))
	var kept: Array = bag.to_save_array()
	check("a carry loaded before the hotbar attaches keeps all thirty cells",
		kept.size() == carry, kept.size())
	check("including what is on key 2",
		kept.size() > grid + 1 and kept[grid + 1] is Dictionary
			and str(kept[grid + 1].get("item_id", "")) == _HB_POTION, kept.slice(grid))

	bar.set_inventory_container(bag)
	var key: Array = bar.slots
	check("attached, the backpack owns thirty cells", bag.slots.size() == carry,
		bag.slots.size())
	check("and key 2 IS cell 21, holding the five potions",
		bag.get_slot_at(grid + 1) == key[1] and _hb_holds(key[1], _HB_POTION, 5),
		key[1].stack.quantity if not key[1].is_empty() else "empty")
	var misnumbered: Array = []
	for i in bag.slots.size():
		if bag.slots[i].slot_index != i:
			misnumbered.append("%d says %d" % [i, bag.slots[i].slot_index])
	check("every cell's slot_index is its position, keys included",
		misnumbered.is_empty(), misnumbered)
	check("every key knows the backpack is its container, not the bar's row",
		key.all(func(s: HotbarSlot) -> bool: return s.home_container == bag))

	# ---- a server answer lands on the keys ----
	bag.load_server_array(_hb_cells({grid + 5: [_HB_POTION, 4]}, carry))
	check("a server layout moves the potions to key 6",
		_hb_holds(key[5], _HB_POTION, 4) and key[1].is_empty(),
		[key[1].is_empty(), key[5].is_empty()])

	# ---- dragging moves, it does not copy ----
	var changes: Array = [0]
	var on_change := func() -> void: changes[0] += 1
	bag.inventory_changed.connect(on_change)

	var cell0: InventorySlot = bag.get_slot_at(0)
	cell0._drop_data(Vector2.ZERO, _hb_drag(key[5]))
	check("dragging key 6 onto bag cell 0 moves the potions into the bag",
		_hb_holds(cell0, _HB_POTION, 4))
	check("AND OFF THE KEY - one place, not two", key[5].is_empty())

	key[0]._drop_data(Vector2.ZERO, _hb_drag(cell0))
	check("dragging them back onto key 1 empties the bag cell",
		_hb_holds(key[0], _HB_POTION, 4) and cell0.is_empty())

	bag.get_slot_at(1).set_stack(ItemStack.new(potion, 3))
	key[0]._drop_data(Vector2.ZERO, _hb_drag(bag.get_slot_at(1)))
	check("more of the same merges onto the key's stack",
		_hb_holds(key[0], _HB_POTION, 7) and bag.get_slot_at(1).is_empty())

	var cell3: InventorySlot = bag.get_slot_at(3)
	cell3.set_stack(ItemStack.new(sword, 1))
	key[0]._drop_data(Vector2.ZERO, _hb_drag(cell3))
	check("something different swaps with it",
		_hb_holds(key[0], _HB_SWORD, 1) and _hb_holds(cell3, _HB_POTION, 7))

	# KEY TO KEY, and counted on its own: neither end is a bag cell, so the only
	# way the backpack hears about it is through the keys' own wiring.
	changes[0] = 0
	key[4]._drop_data(Vector2.ZERO, _hb_drag(key[0]))
	check("key to key moves too", _hb_holds(key[4], _HB_SWORD, 1) and key[0].is_empty())
	check("and a change made entirely on the keys reaches the save",
		changes[0] > 0, changes[0])

	bag._drop_data(Vector2.ZERO, _hb_drag(key[4]))
	check("dropped in a gap in the bag, a key's stack lands in a BAG cell",
		key[4].is_empty() and _hb_holds(bag.get_slot_at(0), _HB_SWORD, 1),
		bag.get_slot_at(0).stack.data.item_id if not bag.get_slot_at(0).is_empty() else "empty")

	# AND A FULL BAG IS FULL. The keys are cells too, and after the grid in
	# `slots`, so "the first empty cell" would happily be key 1.
	for i in range(grid):
		if bag.get_slot_at(i).is_empty():
			bag.get_slot_at(i).set_stack(ItemStack.new(sword, 1))
	key[8].set_stack(ItemStack.new(potion, 2))
	bag._drop_data(Vector2.ZERO, _hb_drag(key[8]))
	check("into a full bag's gap, a key's stack stays on its key",
		_hb_holds(key[8], _HB_POTION, 2) and key[0].is_empty(),
		[key[0].is_empty(), key[8].is_empty()])
	for i in range(grid):
		bag.get_slot_at(i).clear_stack()
	key[8].clear_stack()
	bag.inventory_changed.disconnect(on_change)

	# ---- the keys are not the bag's for everything ----
	bag.set_slot_type("bank")
	check("retyping the grid leaves the keys as keys",
		key.all(func(s: HotbarSlot) -> bool: return s.slot_type == HotbarSlot.HOTBAR_SLOT_TYPE)
			and cell0.slot_type == "bank")
	bag.set_slot_type("inventory")

	# ---- using a key spends the key ----
	key[2].set_stack(ItemStack.new(potion, 2))
	bag.get_slot_at(2).set_stack(ItemStack.new(potion, 6))
	var used: Array = []
	var on_used := func(s: HotbarSlot) -> void: used.append(s)
	bar.slot_used.connect(on_used)
	var relayed: Array = [0]
	var on_relay := func(_s: InventorySlot) -> void: relayed[0] += 1
	bag.slot_right_clicked.connect(on_relay)
	var press := InputEventKey.new()
	press.keycode = KEY_3
	press.pressed = true
	bar._unhandled_input(press)
	check("pressing 3 hands over key 3 itself, not the bag cell with the same potion",
		used.size() == 1 and used[0] == key[2], used)
	used.clear()
	var held := InputEventKey.new()
	held.keycode = KEY_3
	held.pressed = true
	held.echo = true
	bar._unhandled_input(held)
	check("holding it does not drink the stack", used.is_empty(), used)
	key[2].slot_right_clicked.emit(key[2])
	check("a right-click on a key uses it once",
		used.size() == 1 and used[0] == key[2], used.size())
	check("and is not ALSO relayed as a bag right-click, which would use it twice",
		relayed[0] == 0, relayed[0])
	bar.slot_used.disconnect(on_used)
	bag.slot_right_clicked.disconnect(on_relay)

	bag.remove_quantity_at(key[2].slot_index, 1)
	check("the backpack's own removal reaches a key by its cell",
		_hb_holds(key[2], _HB_POTION, 1) and _hb_holds(bag.get_slot_at(2), _HB_POTION, 6))

	# ---- the trash takes a key's stack ----
	var trash_script: Script = load("res://src/ui/inventory/trashslot.gd")
	var trash := PanelContainer.new()
	trash.set_script(trash_script)
	add_child(trash)
	check("the trash accepts a key's stack now that a key holds one",
		trash._can_drop_data(Vector2.ZERO, _hb_drag(key[2])))
	var trashed: Array = [0]
	var on_trashed := func() -> void: trashed[0] += 1
	bag.inventory_changed.connect(on_trashed)
	trash._pending_source_slot = key[2]
	trash._pending_stack = key[2].stack.duplicate_stack()
	trash._on_delete_confirmed()
	check("and deleting it empties the key",
		key[2].is_empty() and not (bag.to_save_array()[grid + 2] is Dictionary))
	# THROUGH THE BACKPACK. A key's parent is the bar's row, which has no
	# request_discard(), and clearing the slot there would tell nobody - the key
	# would look empty and the item would come back on the next load.
	check("THROUGH THE BACKPACK THAT ASKS THE SERVER, not by clearing the slot quietly",
		trashed[0] > 0, trashed[0])
	bag.inventory_changed.disconnect(on_trashed)
	trash.queue_free()

	# ---- the save carries the keys ----
	key[7].set_stack(ItemStack.new(potion, 9))
	var saved: Array = bag.to_save_array()
	check("a save sends every carried cell", saved.size() == carry, saved.size())
	check("with the keys in their own places",
		saved[grid + 7] is Dictionary and int(saved[grid + 7].get("quantity", 0)) == 9,
		saved.slice(grid))

	# ---- a partial set of keys is refused, not shifted ----
	var other := InventoryContainer.new()
	add_child(other)
	await get_tree().process_frame
	other.load_save_array(_hb_cells({grid + 3: [_HB_SWORD, 1]}, carry))
	var gappy: Array = key.duplicate()
	gappy[1] = null
	# The ERROR this prints is the refusal, and is expected in a green run.
	other.attach_remote_slots(gappy)
	check("a hotbar with a key missing is not attached at all",
		other.slots.size() == grid, other.slots.size())
	check("and what was on the keys is still kept for the save",
		other.to_save_array().size() == carry
			and other.to_save_array()[grid + 3] is Dictionary)
	other.queue_free()

	# ---- the wire: no hotbar list either way ----
	var storage := ServerStorage.new()
	var body: Dictionary = storage._save_body(0, {"character": "warrior",
		"hotbar_assignments": ["x", "", ""]})
	check("a save never sends the retired hotbar list", not body.has("hotbar"), body)
	var loaded_slot: Dictionary = storage._slot_from_server({"class_id": "warrior",
		"hotbar": ["x"], "inventory": _hb_cells({grid + 1: [_HB_POTION, 2]}, carry)})
	check("a load makes no hotbar list either",
		not loaded_slot.has("hotbar_assignments"), loaded_slot.keys())
	check("and hands the keys over inside the inventory",
		(loaded_slot.get("inventory", []) as Array).size() == carry)

	# ---- the requests name the cell ----
	# Text, because these reach the network: the server half of each is tested
	# in test_api.py's "THE HOTBAR IS CARRIED".
	var screen: String = _code_only(FileAccess.get_file_as_string(
		"res://src/ui/inventory/inventoryscreen.gd"))
	var at: int = _first_code_index(screen, "func _use_consumable(", 0)
	var end: int = _first_code_index(screen, "\nfunc ", at + 1)
	var post: int = _first_code_index(screen, "/api/character/consume", at)
	check("drinking names the cell drunk from",
		_within(post, end) != -1 and _within(_first_code_index(screen, "\"position\": slot.slot_index", post), end) != -1)
	var bank_src: String = _code_only(FileAccess.get_file_as_string(
		"res://src/ui/bank/bankinventory.gd"))
	at = _first_code_index(bank_src, "func _on_transfer_requested(", 0)
	end = _first_code_index(bank_src, "\nfunc ", at + 1)
	check("a drag into or out of the bank names the cell dragged",
		_within(_first_code_index(bank_src, "source_slot.slot_index", at), end) != -1)
	var cd_src: String = _code_only(FileAccess.get_file_as_string(
		"res://src/systems/characterdata.gd"))
	at = _first_code_index(cd_src, "func equip_item(", 0)
	end = _first_code_index(cd_src, "\nfunc ", at + 1)
	check("equipping sends the cell it came from",
		_within(_first_code_index(cd_src, "body[\"position\"] = position", at), end) != -1)

	# ---- nothing still speaks the old model ----
	var retired := RegEx.new()
	retired.compile("\\b(hotbar_assignments|set_linked_item_ids|is_item_linked|refresh_from_inventory|assigned_item_id|item_used)\\b")
	var speakers: Array[String] = []
	var files: Array[String] = []
	_gd_files_under("res://src", files)
	for path in files:
		if path == "res://src/tools/testrunner.gd":
			continue
		if retired.search(_code_only(FileAccess.get_file_as_string(path))) != null:
			speakers.append(path)
	check("no code still points a key at a bag item", speakers.is_empty(), speakers)
	check("and the scan read the project", files.size() > 50, files.size())

	# ---- the frame hugs the keys ----
	var need: Vector2 = bar.get_combined_minimum_size()
	var hud_path := "res://scene/ui/characterhud.tscn"
	var left: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_left")
	var right: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_right")
	var top: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_top")
	var bottom: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_bottom")
	var given: Vector2 = Vector2(float(right) - float(left), float(bottom) - float(top)) \
		if left != null and right != null and top != null and bottom != null else Vector2.ZERO
	check("the HUD gives the bar exactly the width its keys need",
		is_equal_approx(given.x, need.x),
		"given %s, keys need %s - the difference is empty frame" % [given, need])
	check("and exactly the height", is_equal_approx(given.y, need.y),
		"given %s, need %s" % [given, need])

	bar.queue_free()
	bag.queue_free()
	ItemRegistry._items.erase(_HB_POTION)
	ItemRegistry._items.erase(_HB_SWORD)
	await get_tree().process_frame
	print("  %d keys that hold items: moved, merged, swapped, used, trashed and saved in place"
		% Hotbar.SLOT_COUNT)


func _gd_files_under(dir_path: String, into: Array[String]) -> void:
	"""Every .gd file under dir_path, recursively. Hidden folders skipped."""
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_gd_files_under(dir_path.path_join(sub), into)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			into.append(dir_path.path_join(file))


# =============================================================================
# STAFF DESK - the panel, fed answers, doing what the server's half expects
# =============================================================================
# The server half of this is test_moderation.py: a paged list, a log, notes
# read under reach. The recurring bug in this project is the OTHER half - a
# server that is right and tested and a client that never used it. So this
# builds the real panel and hands it made-up answers in the server's own shape,
# through the same function a real answer lands in (_apply_list_page and its
# two siblings), and reads what it did: what it drew, and what it would ask
# the server next. Nothing here touches the network; the three lines that do
# are pinned by text at the bottom, bounded to the functions they belong in.

func _staff_rows(box: Node) -> Array:
	# Children that are staying. A re-render queue_frees the old rows, and they
	# are still children until the frame ends.
	var out: Array = []
	for child in box.get_children():
		if not child.is_queued_for_deletion():
			out.append(child)
	return out


func _test_the_staff_desk() -> void:
	section("STAFF DESK — a paged list, a record, staff-only notes, and the log")

	var packed: PackedScene = load("res://scene/ui/staff/staffpanel.tscn") as PackedScene
	check("staffpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	# The panel offers by rank, and the rank it reads is Api's. A mod, for
	# the length of this section, and put back after.
	var was_role: String = Api.role
	var was_owner: bool = Api.is_owner
	Api.role = "mod"
	Api.is_owner = false
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	# The log loads the first time its tab is shown. Marked loaded here so the
	# tab switches below measure the panel instead of asking a server.
	panel._log_loaded = true
	await get_tree().process_frame

	# ---- the shape ----
	check("it is attached as a window", panel.get("_window") != null)
	var tabs: TabContainer = panel.tabs
	var detail_tabs: TabContainer = panel.detail_tabs
	check("Players, Log and Reports are tabs",
		tabs.get_tab_count() == 3 and tabs.get_tab_title(0) == "Players" and tabs.get_tab_title(1) == "Log"
			and tabs.get_tab_title(2).begins_with("Reports"),
		[tabs.get_tab_title(0), tabs.get_tab_title(1), tabs.get_tab_title(2) if tabs.get_tab_count() > 2 else ""])
	check("a player's Actions, Record and Trades are tabs",
		detail_tabs.get_tab_count() == 3 and detail_tabs.get_tab_title(0) == "Actions"
		and detail_tabs.get_tab_title(1) == "Record" and detail_tabs.get_tab_title(2) == "Trades",
		[detail_tabs.get_tab_count()])
	check("both sized to their tallest tab, so switching never resizes the window",
		tabs.use_hidden_tabs_for_min_size and detail_tabs.use_hidden_tabs_for_min_size)
	check("the list opens on who is online - who a kick is for",
		panel._show_value() == "online" and panel.show_filter.item_count == panel.SHOW_FILTERS.size(),
		panel._show_value())

	# Picked, so the detail is on screen for the measurements below.
	panel._selected = "rowdy"
	panel._selected_entry = {"username": "rowdy", "role": "player", "actionable": true}
	panel._show_detail(panel._selected_entry)
	var heights: Array[float] = []
	var cut: Array[String] = []
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		for j in (detail_tabs.get_tab_count() if i == 0 else 1):
			if i == 0:
				detail_tabs.current_tab = j
			await get_tree().process_frame
			heights.append(PanelWindow.content_minimum(panel).y)
			for edit in panel.find_children("*", "LineEdit", true, true):
				var line: LineEdit = edit as LineEdit
				if line.placeholder_text == "" or not line.is_visible_in_tree():
					continue
				var box: StyleBox = line.get_theme_stylebox("normal")
				var room: float = line.size.x - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0)
				var need: float = line.get_theme_font("font").get_string_size(line.placeholder_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, line.get_theme_font_size("font_size")).x
				if need > room:
					cut.append("%s needs %d, has %d" % [line.name, need, room])
	check("the window is the same height on every tab", heights.max() == heights.min(), heights)
	check("no input's hint is cut off", cut.is_empty(), cut)
	tabs.current_tab = 0
	detail_tabs.current_tab = 0
	# READ FROM THE SCENE, not the live node: PanelWindow may have restored a
	# rectangle saved by an earlier run, and that is not what a new mod gets.
	var top: float = 0.0
	var bottom: float = 0.0
	var root_state: SceneState = packed.get_state()
	for p in root_state.get_node_property_count(0):
		match root_state.get_node_property_name(0, p):
			"offset_top":
				top = float(root_state.get_node_property_value(0, p))
			"offset_bottom":
				bottom = float(root_state.get_node_property_value(0, p))
	check("its default size holds its tallest tab",
		bottom - top + 0.5 >= heights.max(), "authored %d, needs %d" % [bottom - top, heights.max()])
	check("and it opens clear of the menu bar", 360.0 + bottom <= 720.0 - 76.0, 360.0 + bottom)

	# ---- the list is a page, and asks for the next one ----
	panel._selected = ""
	panel._selected_entry = {}
	panel.search_input.text = "  Row  "
	var params: Dictionary = panel._list_params("fresh")
	check("a search asks the server for the first page of what was typed, trimmed",
		params == {"show": "online", "q": "Row", "limit": panel.PAGE_SIZE}, params)
	var before_gen: int = panel._list_generation
	panel.search_input.text_changed.emit("Ro")
	check("typing waits for a pause rather than asking per keystroke",
		panel._search_countdown > 0.0 and panel._list_generation == before_gen, panel._search_countdown)
	panel._search_countdown = -1.0
	panel.search_input.text = ""

	var amy: Dictionary = {"username": "amy", "role": "player", "online": true, "actionable": true, "record": {}}
	var bob: Dictionary = {"username": "bob", "role": "player", "online": false, "actionable": true,
		"record": {"ban": 1.0, "warn": 2.0, "note": 5.0}}
	var cat: Dictionary = {"username": "cat", "role": "mod", "online": true, "actionable": false, "record": {}}
	panel._apply_list_page({"ok": true, "data": {"accounts": [amy, bob], "more": true,
		"next_after": "bob", "matched": 1204.0, "online": 12.0, "now": 1000.0}}, "fresh")
	await get_tree().process_frame
	check("a page is drawn", _staff_rows(panel.account_list).size() == 2, _staff_rows(panel.account_list).size())
	check("the count is the server's match, not the rows held",
		panel.count_label.text == "2 of 1,204 · 12 online", panel.count_label.text)
	check("and there is a way to the next page", panel.more_button.visible)
	params = panel._list_params("more")
	check("which asks for what comes after the last name, not for page two",
		params.get("after", "") == "bob" and params.get("limit", 0) == panel.PAGE_SIZE, params)

	panel._apply_list_page({"ok": true, "data": {"accounts": [cat], "more": true,
		"next_after": null, "matched": 3.0, "online": 2.0, "now": 1000.0}}, "more")
	await get_tree().process_frame
	var names: Array = _staff_rows(panel.account_list).map(func(r): return str(r.get_meta("username", "")))
	check("the next page is added below, in order", names == ["amy", "bob", "cat"], names)
	check("the last page has no way on", not panel.more_button.visible)
	check("and asks for nothing more", panel._list_params("more").is_empty())
	check("a refresh re-reads a first page's worth", panel._list_params("refresh").get("limit", 0) == panel.PAGE_SIZE)

	var held: Array = []
	for i in 120:
		held.append({"username": "p%03d" % i})
	panel._accounts = held
	check("a refresh re-reads everything loaded, in one request",
		panel._list_params("refresh").get("limit", 0) == 120, panel._list_params("refresh"))
	for i in range(120, 250):
		held.append({"username": "p%03d" % i})
	check("and past the server's largest page, waits for the Refresh button",
		panel._list_params("refresh").is_empty())

	# ---- the row carries the record ----
	panel._apply_list_page({"ok": true, "data": {"accounts": [amy, bob], "more": false,
		"next_after": null, "matched": 2.0, "online": 1.0, "now": 1000.0}}, "fresh")
	await get_tree().process_frame
	var bob_row: Button = null
	for row in _staff_rows(panel.account_list):
		if str(row.get_meta("username", "")) == "bob":
			bob_row = row
	check("a repeat offender's row says so", bob_row != null and bob_row.text.contains("1 ban · 2 warnings"),
		bob_row.text if bob_row != null else "no row")
	check("but not the notes - a note is not a sanction", bob_row != null and not bob_row.text.contains("note"))
	check("clipped to the column, with the whole line on hover",
		bob_row != null and bob_row.clip_text and bob_row.tooltip_text == bob_row.text)

	# ---- the picked player survives a page that does not carry them ----
	panel._selected = "amy"
	panel._selected_entry = amy
	panel._apply_list_page({"ok": true, "data": {"accounts": [bob], "more": false,
		"next_after": null, "matched": 1.0, "online": 0.0, "now": 1000.0}}, "fresh")
	check("a new search does not quietly unpick the player the buttons are aimed at",
		panel.detail_box.visible and panel.name_label.text == "amy", panel.name_label.text)
	var amy_banned: Dictionary = amy.duplicate()
	amy_banned["banned"] = true
	amy_banned["ban"] = {"permanent": true, "banned_by": "thedev", "reason": "x"}
	panel._apply_list_page({"ok": true, "data": {"accounts": [amy_banned, bob], "more": false,
		"next_after": null, "matched": 2.0, "online": 1.0, "now": 1000.0}}, "fresh")
	check("and a page that does carry them updates what the detail says",
		panel.ban_label.text.begins_with("Banned permanently"), panel.ban_label.text)

	# ---- the empty list that is a trap ----
	panel.search_input.text = "rowdy"
	panel._apply_list_page({"ok": true, "data": {"accounts": [], "more": false,
		"next_after": null, "matched": 0.0, "online": 3.0, "now": 1000.0}}, "fresh")
	check("no match under Online says to look at Everyone - the player may just be offline",
		panel.empty_label.visible and panel.empty_label.text.contains("Everyone"), panel.empty_label.text)
	panel.search_input.text = ""

	panel._apply_list_page({"ok": false, "status": 404, "error": "Not found."}, "fresh")
	check("a 404 means this account is no longer staff, and the list goes",
		panel._accounts.is_empty() and panel.notice_label.text.contains("no longer lists you"),
		panel.notice_label.text)

	# ---- notes are offered by reach ----
	panel._show_detail({"username": "rowdy", "role": "player", "actionable": true})
	check("a mod may write a note on a player",
		not panel.note_button.disabled and not panel.warn_button.disabled and panel.note_input.editable)
	panel._show_detail({"username": "cat", "role": "mod", "actionable": false})
	check("but not on another mod - they could not read it back either",
		panel.note_button.disabled and panel.warn_button.disabled and not panel.note_input.editable)

	# ---- the record ----
	panel._selected = "rowdy"
	panel._selected_entry = {"username": "rowdy", "role": "player", "actionable": true}
	panel._record = []
	panel._record_more = false
	panel._record_before = 0
	check("the record asks about the picked player, sanctions and notes first",
		panel._record_params("fresh") == {"player": "rowdy", "limit": panel.RECORD_PAGE_SIZE,
			"action": "moderation"},
		panel._record_params("fresh"))
	panel._record_everything = true
	check("  and everything when asked to show everything",
		not panel._record_params("fresh").has("action"), panel._record_params("fresh"))
	panel._record_everything = false
	check("  from a toggle on the record tab", panel.record_all_button != null
		and panel.record_all_button.toggle_mode and panel.record_all_button.get_parent() == panel.record_list.get_parent().get_parent())
	check("and asks for no older entries before it knows there are some",
		panel._record_params("more").is_empty())
	panel._apply_record_page({"ok": true, "data": {"actions": [
		{"id": 9.0, "at": 1000.0, "by": "themod", "action": "warn", "target": "rowdy", "detail": "spam"},
		{"id": 7.0, "at": 900.0, "by": "themod", "action": "ban", "target": "rowdy", "detail": "1 days: x"},
		{"id": 5.0, "at": 800.0, "by": "themod", "action": "note", "target": "rowdy", "detail": "[color=red]x[/color]"},
	], "more": true, "next_before": 5.0,
		"summary": {"ban": 1.0, "kick": 1.0, "warn": 1.0, "note": 2.0}}}, "fresh")
	await get_tree().process_frame
	var lines: Array = _staff_rows(panel.record_list)
	check("the record is drawn, a line an entry", lines.size() == 3, lines.size())
	check("with the tally of the whole record above it",
		panel.record_summary.text == "Record: 1 ban · 1 kick · 1 warning · 2 notes", panel.record_summary.text)
	check("and the count on the tab, where somebody about to ban is looking",
		detail_tabs.get_tab_title(1) == "Record (3)", detail_tabs.get_tab_title(1))
	check("a note's text is drawn as typed, never as markup",
		lines.size() == 3 and lines[2] is Label and (lines[2] as Label).text.contains("[color=red]x[/color]"))
	var older: Dictionary = panel._record_params("more")
	check("older entries are asked for before the last id shown",
		older.get("before", 0) == 5 and older.get("player", "") == "rowdy", older)
	panel._apply_record_page({"ok": true, "data": {"actions": [
		{"id": 3.0, "at": 700.0, "by": "thedev", "action": "kick", "target": "rowdy", "detail": "1 session(s)"},
	], "more": false, "next_before": null, "summary": {"ban": 1.0, "kick": 1.0, "warn": 1.0, "note": 2.0}}}, "more")
	await get_tree().process_frame
	check("and added below", _staff_rows(panel.record_list).size() == 4 and not panel.record_more.visible)
	panel._apply_record_page({"ok": true, "data": {"actions": [], "more": false, "summary": {}}}, "fresh")
	check("a clean record says so, and the tab loses its count",
		panel.record_summary.text == "Record: clean" and detail_tabs.get_tab_title(1) == "Record"
		and panel.record_empty.visible, [panel.record_summary.text, detail_tabs.get_tab_title(1)])

	# ---- the log ----
	check("the kind filter opens on Moderation, with Everything next to it",
		panel.log_kind.item_count == 2 and panel.log_kind.selected == 0
		and panel._log_kind_value() == "moderation" and str(panel.log_kind.get_item_metadata(1)) == "",
		[panel.log_kind.item_count, panel.log_kind.selected])
	var log_page: Dictionary = {"ok": true, "data": {"actions": [
		{"id": 41.0, "at": 1000.0, "by": "themod", "action": "kick", "target": "rowdy", "detail": ""},
		{"id": 40.0, "at": 990.0, "by": "thedev", "action": "guild_rename", "target": "Shared", "detail": "-> Other"},
	], "more": true, "next_before": 40.0, "kinds": ["ban", "kick", "warn", "smite"]}}
	panel._apply_log_page(log_page, "fresh")
	await get_tree().process_frame
	var kinds_shown: Array = []
	for i in panel.log_kind.item_count:
		kinds_shown.append(panel.log_kind.get_item_text(i))
	check("and fills from the server's own list of kinds",
		kinds_shown == ["Moderation", "Everything", "Bans", "Kicks", "Warnings", "smite"], kinds_shown)
	var entries: Array = _staff_rows(panel.log_entries)
	check("the log is drawn", entries.size() == 2, entries.size())
	check("a line about a player takes you to them",
		entries.size() == 2 and (entries[0] as Control).mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	check("a line about a guild does not pretend to",
		entries.size() == 2 and (entries[1] as Control).mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND)
	var second: Dictionary = log_page.duplicate(true)
	second["data"]["kinds"] = ["ban"]
	second["data"]["more"] = false
	second["data"]["next_before"] = null
	panel._apply_log_page(second, "more")
	await get_tree().process_frame
	check("the kinds are filled once, not reset under somebody's cursor", panel.log_kind.item_count == 6)
	check("older entries go below", _staff_rows(panel.log_entries).size() == 4 and not panel.log_more.visible)

	for i in panel.log_kind.item_count:
		if str(panel.log_kind.get_item_metadata(i)) == "warn":
			panel.log_kind.select(i)
	panel.log_player.text = " Rowdy "
	params = panel._log_params("fresh")
	check("the log's filters go to the server, trimmed",
		params == {"player": "Rowdy", "staff": "", "action": "warn", "limit": panel.PAGE_SIZE}, params)
	check("and the one left empty is not sent",
		panel.build_query(params) == "?player=Rowdy&action=warn&limit=%d" % panel.PAGE_SIZE,
		panel.build_query(params))

	# ---- the wiring no bare panel can prove ----
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/staff/staffpanel.gd"))
	var wired := func(fn: String, needle: String) -> bool:
		var at: int = _first_code_index(src, "func %s(" % fn, 0)
		var end: int = _first_code_index(src, "\nfunc ", at + 1)
		return at != -1 and _within(_first_code_index(src, needle, at), end) != -1
	check("the list asks the server with the list's own question",
		wired.call("_load", "Api.get_json(\"/api/staff/users\" + build_query(params))")
		and wired.call("_load", "_list_params(mode)") and wired.call("_load", "_apply_list_page(res, mode)"))
	check("a stale answer is dropped rather than drawn",
		wired.call("_load", "generation != _list_generation"))
	check("the record asks the log about the picked player",
		wired.call("_load_record", "Api.get_json(\"/api/staff/actions\" + build_query(params))")
		and wired.call("_load_record", "_apply_record_page(res, mode)"))
	check("and drops an answer about somebody no longer picked",
		wired.call("_load_record", "username != _selected"))
	check("picking a player reads their record", wired.call("_pick", "_load_record(\"fresh\")"))
	check("acting on a player re-reads their record", wired.call("_perform", "_load_record(\"fresh\")"))
	check("the log tab asks the log",
		wired.call("_load_log", "Api.get_json(\"/api/staff/actions\" + build_query(params))")
		and wired.call("_load_log", "_apply_log_page(res, mode)"))
	check("the log is read when its tab is first opened", wired.call("_on_tab_changed", "_load_log(\"fresh\")"))
	check("a note is sent with its kind",
		wired.call("_on_note_pressed", "Api.post(\"/api/staff/note\"")
		and wired.call("_on_note_pressed", "\"kind\": kind"))
	check("the warning button logs a warning and the note button a note",
		wired.call("_ready", "warn_button.pressed.connect(_on_note_pressed.bind(\"warn\"))")
		and wired.call("_ready", "note_button.pressed.connect(_on_note_pressed.bind(\"note\"))"))
	check("a log line opens its player", wired.call("_on_entry_input", "_open_player(username)"))
	check("across everyone, not just who is online", wired.call("_open_player", "== \"all\""))

	# ---- THE DOOR ----
	# For as long as this panel existed, NOTHING OPENED IT. characterhud.tscn
	# carried a hidden Staff button, _add_owner_button() hid its whole row
	# from everybody but the owner, and no line anywhere instanced the panel -
	# while this file tested the panel itself, thoroughly, in isolation. So a
	# mod had no way in, and every check above was about a room with no door.
	# These build the real HUD (out of the tree: its _ready() starts polls)
	# and ask the row who it is for, and what the button is connected to.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var staff_row: Control = hud.get_node_or_null("%staffrow") as Control
	var staff_button: Button = hud.get_node_or_null("%staffbutton") as Button
	check("the HUD has the staff row and its button", staff_row != null and staff_button != null)
	if staff_row != null and staff_button != null:
		Api.role = "player"
		hud._add_owner_button()
		check("a player has no staff row", not staff_row.visible)
		Api.role = "mod"
		hud._add_owner_button()
		check("a mod has the row, with the Staff button showing", staff_row.visible and staff_button.visible)
		check("and the button opens the desk",
			staff_button.pressed.is_connected(Callable(hud, "_toggle_staff_panel")))
		check("but a mod gets none of the owner's buttons",
			not staff_row.has_node("ownerbutton") and not staff_row.has_node("powersbutton"))
		Api.role = "owner"
		Api.is_owner = true
		hud._add_owner_button()
		check("the owner gets Staff, Owner and Powers",
			staff_button.visible and staff_row.has_node("ownerbutton") and staff_row.has_node("powersbutton"))
		Api.is_owner = false
		Api.role = "mod"
	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var toggle_at: int = _first_code_index(hud_src, "func _toggle_staff_panel(", 0)
	var toggle_end: int = _first_code_index(hud_src, "\nfunc ", toggle_at + 1)
	check("the toggle builds the desk from its scene and opens it",
		_within(_first_code_index(hud_src, "STAFF_PANEL_SCENE.instantiate()", toggle_at), toggle_end) != -1
		and _within(_first_code_index(hud_src, "staff_panel.toggle_panel()", toggle_at), toggle_end) != -1)
	# ESCAPE, with the real panel standing in as the HUD's.
	hud.staff_panel = panel
	panel.visible = true
	check("Escape counts the desk as open", hud.is_panel_open())
	hud.hide_panel()
	check("and closes it", not panel.visible)
	hud.staff_panel = null
	hud.free()

	panel.queue_free()
	Api.role = was_role
	Api.is_owner = was_owner
	await get_tree().process_frame
	print("  a desk a mod can run while the owner is away: pages, a record, notes and a log")


# =============================================================================
# THE GUILD PANEL - a name that is never cut, a roster by rank, and room to act
# =============================================================================
# Reported with a screenshot: a guild called "the first" whose own panel called
# it "the". The name shared one row with the line about it, and a Label sharing
# a row gives way - so the guild's name was the thing trimmed to make room for
# a sentence about the guild. Beside that: an "R" nobody could read as refresh,
# a heading that was the VIEWER's rank printed over everybody, "+" and "-" for
# online, three tiny buttons on every row, and Leave and Disband doing the same
# thing for a leader alone. All of it is checked by building the real panel and
# handing it answers in the server's shape through _repaint(), the function a
# real answer lands in.

func _guild_rows_of(panel: Node) -> Array:
	var out: Array = []
	for child in panel.rows.get_children():
		if not child.is_queued_for_deletion():
			out.append(child)
	return out


func _guild_texts(node: Node) -> Array:
	# Every Label and Button text under `node`, in tree order.
	var out: Array = []
	for child in node.find_children("*", "", true, false):
		if (child is Label or child is Button) and child.is_visible_in_tree():
			out.append(str(child.text))
	return out


func _guild_member_frame(panel: Node, who: String) -> PanelContainer:
	for row in _guild_rows_of(panel):
		if row is PanelContainer and str(row.get_meta("username", "")) == who:
			return row
	return null


func _test_the_guild_panel_reads_well() -> void:
	section("GUILD PANEL — the name fits, the roster is by rank, actions open on click")

	var packed: PackedScene = load("res://scene/ui/guild/guildpanel.tscn") as PackedScene
	check("guildpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var was_name: String = Api.username
	Api.username = "Tunacan"
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame

	var now: int = int(Time.get_unix_time_from_system())
	var solo: Dictionary = {"in_guild": true, "rank": "leader", "invites": [], "now": now,
		"cost": 5000, "guild": {"name": "the first", "tag": "THE FIRST", "created_at": now - 86400,
		"members": [{"username": "Tunacan", "role": "owner", "rank": "leader",
			"online": true, "last_seen_at": now}], "size": 1, "capacity": 50}}

	# ---- the header ----
	var fits := func(label: Label) -> bool:
		var need: float = label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		return label.size.x + 0.5 >= need
	panel._repaint(solo)
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Label = panel.title
	check("the guild's name is drawn whole, not cut to make room for a sentence about it",
		title.text == "the first" and fits.call(title), [title.text, title.size.x])
	var legacy: Dictionary = solo.duplicate(true)
	legacy["guild"]["name"] = "Twenty Four Characters!!"
	panel._repaint(legacy)
	await get_tree().process_frame
	await get_tree().process_frame
	check("so is the longest name a guild from before the twelve-character cap can have",
		fits.call(title), title.size.x)
	panel._repaint(solo)
	await get_tree().process_frame
	check("the tag is drawn in the tag's own colour, as it is beside a name in chat",
		panel.tag_label.visible and panel.tag_label.text == "[THE FIRST]"
		and panel.tag_label.get_theme_color("font_color") == Api.GUILD_TAG_COLOUR, panel.tag_label.text)
	check("a guild of one says so in words, not arithmetic",
		panel.count_label.text.begins_with("just you") and not panel.count_label.text.contains("of 1"),
		panel.count_label.text)
	var header: Node = panel.get_node("frame/margin/rows/headerpanel")
	var letters: Array = []
	for b in header.find_children("*", "Button", true, false):
		letters.append((b as Button).text)
	check("the header has one button, the same × as every other panel", letters == ["×"], letters)
	check("and no R: the roster re-reads itself", panel.get_node_or_null("%guildrefreshbutton") == null)

	# ---- the guide, where the empty space was ----
	var solo_text: String = " ".join(_guild_texts(panel.rows))
	check("a new guild is told what its tag is for",
		solo_text.contains("[THE FIRST] is your guild's tag"), solo_text)
	check("how to invite", solo_text.contains("Invite somebody by typing their name above"))
	check("and where to talk", solo_text.contains("Guild tab in chat"))

	# ---- the footer ----
	check("a leader alone has one way out, called what it does",
		not panel.leave_button.visible and panel.disband_button.visible
		and panel.disband_button.text == "Close the guild",
		[panel.leave_button.visible, panel.disband_button.text])

	# ---- the roster, by rank ----
	# Deliberately NOT in the server's order: the headings must not depend on it.
	var full: Dictionary = solo.duplicate(true)
	full["guild"]["members"] = [
		{"username": "p001", "role": "player", "rank": "member", "online": false, "last_seen_at": now - 5 * 86400},
		{"username": "rowdy", "role": "player", "rank": "officer", "online": true, "last_seen_at": now},
		{"username": "Tunacan", "role": "owner", "rank": "leader", "online": true, "last_seen_at": now},
		{"username": "quietone", "role": "mod", "rank": "officer", "online": false, "last_seen_at": now - 7200},
		{"username": "newbie", "role": "player", "rank": "member", "online": true, "last_seen_at": now},
	]
	full["guild"]["size"] = 5
	panel._repaint(full)
	await get_tree().process_frame
	var headings: Array = []
	for row in _guild_rows_of(panel):
		if row is Label and not (row as Label).autowrap_mode:
			headings.append((row as Label).text)
	check("each rank under its own heading, leader first, with counts",
		headings == ["Leader", "Officers · 2", "Members · 2"], headings)
	check("the header counts the guild", panel.count_label.text.begins_with("5 members, 3 online"),
		panel.count_label.text)
	check("and a guild with people in it gets no beginner's guide",
		not " ".join(_guild_texts(panel.rows)).contains("Getting started"))

	var me_frame: PanelContainer = _guild_member_frame(panel, "Tunacan")
	var rowdy: PanelContainer = _guild_member_frame(panel, "rowdy")
	var quiet: PanelContainer = _guild_member_frame(panel, "quietone")
	check("every member has a row", me_frame != null and rowdy != null and quiet != null)
	if me_frame == null or rowdy == null or quiet == null:
		panel.queue_free()
		Api.username = was_name
		return
	var me_texts: Array = _guild_texts(me_frame)
	check("online is a filled dot and offline a hollow one - shapes, not + and -",
		me_texts.has("●") and _guild_texts(quiet).has("○")
		and not me_texts.has("+") and not _guild_texts(quiet).has("-"), [me_texts, _guild_texts(quiet)])
	check("your own row says it is you", me_texts.has("you"), me_texts)
	check("an online row does not say 'online' beside the dot that already does",
		not me_texts.has("online"), me_texts)
	check("an offline row says when", _guild_texts(quiet).has("2 h ago"), _guild_texts(quiet))

	# ---- actions on click ----
	check("rows carry no buttons until they are opened",
		rowdy.find_children("*", "Button", true, false).is_empty())
	check("your own row offers nothing and does not pretend to",
		me_frame.mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND and not me_texts.has("▸"))
	check("a row with something to offer says so", _guild_texts(quiet).has("▸"), _guild_texts(quiet))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	quiet.gui_input.emit(click)
	await get_tree().process_frame
	quiet = _guild_member_frame(panel, "quietone")
	var offered: Array = []
	for b in quiet.find_children("*", "Button", true, false):
		offered.append((b as Button).text)
	check("clicking an officer's row opens what the leader may do to them",
		offered == ["Demote", "Make leader", "Remove"], offered)
	check("and only that row", _guild_member_frame(panel, "rowdy").find_children("*", "Button", true, false).is_empty())

	panel._repaint(panel._last_data)
	await get_tree().process_frame
	quiet = _guild_member_frame(panel, "quietone")
	check("the fifteen-second refresh redraws it still open",
		quiet.find_children("*", "Button", true, false).size() == 3)

	# REMOVE ASKS TWICE. Pressed once it arms and says what the second press
	# does; nothing is sent. (A second press would reach the server.)
	var remove: Button = null
	for b in quiet.find_children("*", "Button", true, false):
		if str(b.get_meta("action", "")) == "remove":
			remove = b
	# NULL-SAFE: with the row not open there is no Remove to press, and an error
	# here would end the section and hide every check below it.
	check("the open row has a Remove to press", remove != null)
	if remove != null:
		remove.pressed.emit()
	await get_tree().process_frame
	quiet = _guild_member_frame(panel, "quietone")
	var armed_texts: Array = _guild_texts(quiet)
	check("Remove asks before it removes", armed_texts.has("Sure?") and not panel._busy, armed_texts)
	check("and says what the second press will do", panel.notice.text.contains("remove quietone"),
		panel.notice.text)
	panel._armed["until"] = 0.0
	panel._repaint(panel._last_data)
	await get_tree().process_frame
	check("an arm that has run out reads Remove again",
		_guild_texts(_guild_member_frame(panel, "quietone")).has("Remove"))

	quiet = _guild_member_frame(panel, "quietone")
	quiet.gui_input.emit(click)
	await get_tree().process_frame
	check("clicking the open row closes it",
		_guild_member_frame(panel, "quietone").find_children("*", "Button", true, false).is_empty())

	check("a leader with people under them keeps Leave and Disband",
		panel.leave_button.visible and panel.disband_button.visible and panel.disband_button.text == "Disband")

	# ---- the same guild, seen by a member ----
	var as_member: Dictionary = full.duplicate(true)
	as_member["rank"] = "member"
	Api.username = "p001"
	panel._open_member = ""
	panel._repaint(as_member)
	await get_tree().process_frame
	headings = []
	for row in _guild_rows_of(panel):
		if row is Label and not (row as Label).autowrap_mode:
			headings.append((row as Label).text)
	check("a member sees the same headings - not 'Member' printed over the leader",
		headings == ["Leader", "Officers · 2", "Members · 2"], headings)
	var arrows: int = 0
	for row in _guild_rows_of(panel):
		if row is PanelContainer and _guild_texts(row).has("▸"):
			arrows += 1
	check("and is offered nothing on anybody's row", arrows == 0, arrows)
	check("and only Leave in the footer", panel.leave_button.visible and not panel.disband_button.visible)

	# ---- names in their own colours, rank as marks, who they are playing ----
	var rich: Dictionary = full.duplicate(true)
	rich["rank"] = "leader"
	rich["guild"]["members"] = [
		{"username": "p001", "role": "player", "rank": "member", "online": false,
			"last_seen_at": now - 5 * 86400, "name_hue": null, "character": "", "class_id": "", "level": 0, "area": ""},
		{"username": "quietone", "role": "mod", "rank": "officer", "online": false,
			"last_seen_at": now - 7200, "name_hue": 140, "character": "Quill", "class_id": "healer", "level": 22, "area": "elusion"},
		{"username": "Tunacan", "role": "owner", "rank": "leader", "online": true,
			"last_seen_at": now, "name_hue": 200, "character": "Kaelen", "class_id": "warrior", "level": 12, "area": "elusion"},
		{"username": "rowdy", "role": "player", "rank": "officer", "online": true,
			"last_seen_at": now, "name_hue": 20, "character": "Rowan", "class_id": "mage", "level": 7, "area": "field"},
		{"username": "newbie", "role": "dev", "rank": "member", "online": true,
			"last_seen_at": now, "name_hue": 300, "character": "Vex", "class_id": "tank", "level": 3, "area": "bossarena"},
	]
	rich["guild"]["activity"] = [
		{"at": now - 30, "kind": "promoted", "actor": "Tunacan", "target": "rowdy", "detail": "officer"},
		{"at": now - 86400 - 5, "kind": "renamed", "actor": "", "target": "the first", "detail": "old name"},
		{"at": now - 3 * 86400, "kind": "shrugged", "actor": "rowdy", "target": ""},
	]
	Api.username = "Tunacan"
	panel._open_member = ""
	panel._repaint(rich)
	await get_tree().process_frame

	var order: Array = []
	for row in _guild_rows_of(panel):
		if row is PanelContainer and row.has_meta("username"):
			order.append(str(row.get_meta("username")))
	check("inside each rank, whoever is on right now comes first",
		order == ["Tunacan", "rowdy", "quietone", "newbie", "p001"], order)

	var name_of := func(who: String) -> Label:
		var f: PanelContainer = _guild_member_frame(panel, who)
		return f.find_child("name", true, false) as Label if f != null else null
	var rowdy_name: Label = name_of.call("rowdy")
	check("a name is drawn in the colour its player chose",
		rowdy_name != null and rowdy_name.get_theme_color("font_color") == NameTag.colour(20))
	var p001_name: Label = name_of.call("p001")
	check("and a member who never chose one in the default",
		p001_name != null and p001_name.get_theme_color("font_color") == NameTag.colour(null))
	var owner_row: PanelContainer = _guild_member_frame(panel, "Tunacan")
	check("the server's owner wears the crown in the guild too",
		owner_row != null and owner_row.find_children("*", "TextureRect", true, false).size() == 1)
	check("a mod wears MOD, a dev DEV",
		_guild_texts(_guild_member_frame(panel, "quietone")).has("MOD")
		and _guild_texts(_guild_member_frame(panel, "newbie")).has("DEV"))
	var mark_of := func(who: String) -> Label:
		var f: PanelContainer = _guild_member_frame(panel, who)
		return f.find_child("rankmark", true, false) as Label if f != null else null
	var lead_mark: Label = mark_of.call("Tunacan")
	var off_mark: Label = mark_of.call("rowdy")
	check("the guild leader wears a gold crown mark",
		lead_mark != null and lead_mark.text == "♛"
		and lead_mark.get_theme_color("font_color") == panel.RANK_COLOURS["leader"])
	check("an officer a blue diamond",
		off_mark != null and off_mark.text == "◆"
		and off_mark.get_theme_color("font_color") == panel.RANK_COLOURS["officer"])
	check("and a member nothing", mark_of.call("p001") == null)
	var gold_heading: bool = false
	for r in _guild_rows_of(panel):
		if r is Label and (r as Label).text == "Leader":
			gold_heading = (r as Label).get_theme_color("font_color") == panel.RANK_COLOURS["leader"]
	check("the headings wear the same rank colours", gold_heading)

	var char_of := func(who: String) -> String:
		var f: PanelContainer = _guild_member_frame(panel, who)
		var l: Label = f.find_child("character", true, false) as Label if f != null else null
		return l.text if l != null else ""
	check("under each name, who they are playing",
		char_of.call("rowdy") == "Rowan · Mage · lvl 7", char_of.call("rowdy"))
	check("and nothing invented for a member with no character", char_of.call("p001") == "")
	var where_of := func(who: String) -> String:
		var f: PanelContainer = _guild_member_frame(panel, who)
		var l: Label = f.find_child("where", true, false) as Label if f != null else null
		return l.text if l != null else ""
	check("somebody on right now shows where they are", where_of.call("rowdy") == "in Field",
		where_of.call("rowdy"))
	check("somebody away shows when they were last on, never where",
		where_of.call("quietone") == "2 h ago", where_of.call("quietone"))

	check("the header bar shows how full the guild is",
		panel.fill_bar.visible and int(panel.fill_bar.value) == 5 and int(panel.fill_bar.max_value) == 50,
		[panel.fill_bar.visible, panel.fill_bar.value, panel.fill_bar.max_value])

	# ---- the history ----
	var history: Array = []
	var in_history: bool = false
	for row in _guild_rows_of(panel):
		if row is Label and (row as Label).text == "Recent activity":
			in_history = true
		elif in_history and row is HBoxContainer:
			history.append(" ".join(_guild_texts(row)))
	check("the guild's recent history is at the bottom, newest first",
		history.size() == 3 and history[0] == "just now Tunacan made rowdy an officer", history)
	check("a staff rename says what the guild was called and not who did it",
		history.size() == 3 and history[1] == "1 day ago Staff renamed the guild from old name", history)
	check("and a kind this build has never heard of still reads as a sentence",
		history.size() == 3 and history[2] == "3 days ago rowdy shrugged", history)

	# ---- the row lights up under the pointer ----
	var hover: PanelContainer = _guild_member_frame(panel, "rowdy")
	hover.mouse_entered.emit()
	check("a row you can act on lights up under the pointer", hover.has_theme_stylebox_override("panel"))
	hover.mouse_exited.emit()
	check("and goes back when the pointer leaves", not hover.has_theme_stylebox_override("panel"))
	var still: PanelContainer = _guild_member_frame(panel, "Tunacan")
	check("your own row, with nothing to offer, does not light up",
		still.get_signal_connection_list("mouse_entered").is_empty())

	# ---- invitations ----
	var invited: Dictionary = {"in_guild": false, "rank": "", "now": now, "cost": 5000,
		"invites": [{"guild": "Dave's Lads", "by": "dave", "at": now}]}
	panel._repaint(invited)
	await get_tree().process_frame
	var answers: Array = []
	for b in panel.rows.find_children("*", "Button", true, false):
		answers.append([(b as Button).text, (b as Button).size.x >= 60.0])
	check("an invitation is answered with Join or Decline, each wide enough to read",
		answers == [["Join", true], ["Decline", true]], answers)
	check("outside a guild the header says what founding one costs",
		panel.count_label.text.contains("to found one") and not panel.tag_label.visible
		and not panel.fill_bar.visible)

	# ---- the rules, pure ----
	var script: Script = panel.get_script()
	check("a leader may demote, hand on or remove an officer",
		Array(script.actions_for("leader", "boss", "o", "officer")) == ["demote", "handon", "remove"])
	check("an officer may only remove a member",
		Array(script.actions_for("officer", "o1", "m", "member")) == ["remove"])
	check("nobody is offered anything against an equal",
		script.actions_for("officer", "o1", "o2", "officer").is_empty())
	check("or against themselves, whatever the case of the name",
		script.actions_for("leader", "Boss", "boss", "member").is_empty())
	check("a rank this build has never heard of is offered nothing",
		script.actions_for("warlord", "x", "m", "member").is_empty())
	check("history says 'just now', '1 day ago' - not '0 min', not '1 days'",
		script.ago_text(now - 10, now) == "just now" and script.ago_text(now - 86400, now) == "1 day ago"
		and script.ago_text(now - 3 * 86400, now) == "3 days ago")
	check("a sighting seconds old is 'just now', never '0 min ago' (one rule, LocalTime.ago)",
		script.presence_text({"last_seen_at": now - 20}, now) == "just now"
		and script.presence_text({"last_seen_at": now - 86400}, now) == "1 day ago",
		script.presence_text({"last_seen_at": now - 20}, now))

	panel.queue_free()
	Api.username = was_name
	await get_tree().process_frame
	print("  a guild panel that names its guild, groups its people and keeps its buttons until asked")


# =============================================================================
# TRADES — the right person, the offer you saw, and the result reaches you
# =============================================================================
# Four defects, all found by driving a trade between two accounts:
#
#   the invitee was never told: nothing polled the trade unless the window was
#     already open, so a trade sat unseen until it expired
#   a typed name went to the other player's FIRST character, not the one they
#     were playing (the window sent to_slot 0)
#   Accept agreed to whatever was standing when it landed, so an offer swapped
#     a moment before the click was accepted as the swap
#   whoever accepted FIRST was told nothing, kept the old bag on screen, and
#     their next save - a whole-bag replace - deleted what they had received
#
# The server halves are held by test_trades.py. These are the client halves:
# the window, the HUD and the save path, each driven with made-up answers in
# the exact shape the server sends.

func _trade_payload(revision: int, their_items: Array, their_gold: int = 0,
		they_online: bool = true, they_accepted: bool = false, we_accepted: bool = false) -> Dictionary:
	return {
		"trade_id": "t-one", "state": "open", "revision": revision,
		"a": {"username": "tester", "name": "Aldra", "level": 9, "role": "player",
			"name_hue": null, "slot": 0, "items": [], "gold": 0, "confirmed": we_accepted,
			"offering_value": 0, "tax": 5 if their_gold > 0 or not their_items.is_empty() else 0,
			"online": true},
		"b": {"username": "bob", "name": "Bram", "level": 7, "role": "mod",
			"name_hue": 200, "slot": 1, "items": their_items, "gold": their_gold,
			"confirmed": they_accepted, "offering_value": 100 + their_gold, "tax": 0,
			"online": they_online},
	}


func _test_trades_reach_the_right_people() -> void:
	section("TRADES — the right person, the offer you saw, and the result reaches you")

	var TradePanel: Script = load("res://src/ui/trade/tradepanel.gd") as Script
	var packed: PackedScene = load("res://scene/ui/trade/tradepanel.tscn") as PackedScene
	check("tradepanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate() or TradePanel == null:
		return

	var was_name: String = Api.username
	Api.username = "tester"
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame

	# ---- a typed name is a person, not a slot ----
	var typed: Dictionary = panel._offer_body("bob", -1)
	check("an offer to a typed name sends no slot for them - the server picks who they are playing",
		not typed.has("to_slot") and typed.get("username") == "bob", typed)
	var picked: Dictionary = panel._offer_body("bob", 1)
	check("one picked off the nearby list sends the slot the server listed",
		int(picked.get("to_slot", -1)) == 1, picked)
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/trade/tradepanel.gd"))
	var pressed_at: int = src.find("func _on_offer_pressed")
	var pressed_end: int = src.find("\nfunc ", pressed_at + 10)
	check("and the Open trade button is the typed path",
		_within(src.find("_send_offer(who, -1)", pressed_at), pressed_end) != -1
		and _within(src.find("_send_offer(who, 0)", pressed_at), pressed_end) == -1)

	# ---- drawing a trade ----
	var sword: Array = [{"item_id": "ironsword", "quantity": 2}]
	panel._apply_poll({"trade": _trade_payload(3, sword), "resync": null})
	await get_tree().process_frame
	check("an open trade shows the trade, not the list", panel.trade_box.visible and not panel.start_box.visible)
	check("the window remembers which revision it drew", panel._revision == 3, panel._revision)
	check("and Accept sends exactly that", panel._confirm_body() == {"revision": 3}, panel._confirm_body())
	var name_label: Label = panel.with_row.get_node_or_null("name") as Label
	check("who it is with: their character, in the colour they chose",
		name_label != null and name_label.text == "Bram"
		and name_label.get_theme_color("font_color") == NameTag.colour(200),
		name_label.text if name_label else null)
	check("with their rank as a badge", panel.with_row.get_node_or_null("badge") != null)
	var detail: Label = panel.with_row.get_node_or_null("detail") as Label
	check("and their account and level", detail != null and detail.text == "(bob) · lv 7",
		detail.text if detail else null)
	var dot: Label = panel.with_row.get_node_or_null("presence") as Label
	check("with a presence dot", dot != null and dot.text == "●")
	var their_row: Node = panel.them_list.get_node_or_null("item_ironsword")
	check("their item is drawn as a row with an icon's space kept",
		their_row != null and their_row.get_node_or_null("icon") != null
		and (their_row.get_node("icon") as Control).custom_minimum_size == TradePanel.ICON_SIZE)
	var qty: Label = their_row.get_node_or_null("quantity") as Label if their_row else null
	check("and its quantity", qty != null and qty.text == "x2", qty.text if qty else null)
	check("and its tooltip says what it is", their_row != null
		and str((their_row as Control).tooltip_text).length() > 0)
	check("the Decline button is only for the asked; the opener gets Cancel trade",
		panel.cancel_button.text == "Cancel trade", panel.cancel_button.text)

	# ---- a change is pointed out, not slipped in ----
	panel._set_notice("", false)
	panel._apply_poll({"trade": _trade_payload(3, sword), "resync": null})
	check("the same offer read again says nothing", panel.notice_label.text == "", panel.notice_label.text)
	var stick: Array = [{"item_id": "tinyhealthpotion", "quantity": 1}]
	panel._apply_poll({"trade": _trade_payload(4, stick), "resync": null})
	check("a changed offer is pointed out by name",
		panel.notice_label.text.contains("Bram changed their offer"), panel.notice_label.text)
	check("the column that changed is lit", panel.them_panel.modulate != Color.WHITE, panel.them_panel.modulate)
	check("and Accept now names the new revision", panel._confirm_body() == {"revision": 4})
	panel._set_notice("", false)
	panel._apply_poll({"trade": _trade_payload(5, stick, 1), "resync": null})
	check("a change of one gold is a change too",
		panel.notice_label.text.contains("changed their offer"), panel.notice_label.text)

	# ---- the answer to Accept ----
	panel._set_notice("", false)
	panel._apply_confirm({"ok": false, "status": 409, "error": "The offer changed.",
		"data": {"error": "Conflict", "trade": _trade_payload(6, sword, 50)}}, null)
	check("an accept refused because the offer moved redraws the offer as it now stands",
		panel._revision == 6 and panel.them_gold.text == "Gold 50", [panel._revision, panel.them_gold.text])
	check("and says why, by name",
		panel.notice_label.text.contains("changed the offer before your accept arrived"), panel.notice_label.text)

	# ---- the four states of Accept ----
	var us: Dictionary = {"confirmed": false}
	var them: Dictionary = {"name": "Bram", "confirmed": false, "online": true}
	check("nobody has accepted: Accept", TradePanel.accept_state(us, them)["text"] == "Accept")
	check("they have: it says so, still live",
		TradePanel.accept_state(us, {"name": "Bram", "confirmed": true, "online": true})["text"] == "Accept (Bram has)"
		and not TradePanel.accept_state(us, {"name": "Bram", "confirmed": true, "online": true})["disabled"])
	check("you have: waiting, and the button is spent",
		TradePanel.accept_state({"confirmed": true}, them)["disabled"]
		and str(TradePanel.accept_state({"confirmed": true}, them)["text"]).begins_with("Waiting for Bram"))
	check("they have gone offline: nothing to accept against",
		TradePanel.accept_state(us, {"name": "Bram", "online": false})["disabled"]
		and str(TradePanel.accept_state(us, {"name": "Bram", "online": false})["text"]).contains("offline"))
	panel._apply_poll({"trade": _trade_payload(6, sword, 50, false), "resync": null})
	check("an offline partner disables Accept in the window, and says so",
		panel.confirm_button.disabled and panel.notice_label.text.contains("gone offline"),
		[panel.confirm_button.disabled, panel.notice_label.text])
	check("the dot goes hollow", (panel.with_row.get_node_or_null("presence") as Label).text == "○")
	check("the asked side can Decline", TradePanel.cancel_text("b", {"confirmed": false}) == "Decline")
	check("but not once they have agreed to something",
		TradePanel.cancel_text("b", {"confirmed": true}) == "Cancel trade")

	# ---- the line above the buttons ----
	check("the summary quotes the server's cut",
		TradePanel.summary_text({"tax": 5}, {"offering_value": 100})
			== "You receive 100 gold's worth. The kingdom takes 5 gold from you.")
	check("an item the server cannot value is said plainly, never 'worth 0'",
		TradePanel.summary_text({"tax": null}, {"offering_value": null}).contains("cannot go through")
		and not TradePanel.worth_text(null).contains("0"))
	check("nothing offered yet", TradePanel.summary_text({"tax": 0}, {"offering_value": 0}) == "You receive nothing yet.")

	# ---- how it ended ----
	panel._apply_poll({"trade": null, "resync": null, "last": {"trade_id": "t-one", "state": "cancelled"}})
	check("a trade the other side called off says so",
		panel.notice_label.text == "The trade was called off." and panel.start_box.visible,
		panel.notice_label.text)
	check("and the window stops watching it", panel._watched_trade_id == "")
	panel._apply_poll({"trade": _trade_payload(1, sword), "resync": null})
	panel._apply_poll({"trade": null, "resync": null, "last": {"trade_id": "t-one", "state": "done"}})
	check("one that finished - result already delivered by the HUD's poll - says complete",
		panel.notice_label.text == "Trade complete.", panel.notice_label.text)
	panel._apply_poll({"trade": _trade_payload(1, sword), "resync": null})
	panel._apply_poll({"trade": null, "resync": null, "last": {"trade_id": "some-other", "state": "done"}})
	check("one that simply vanished expired", panel.notice_label.text == "The trade expired.",
		panel.notice_label.text)
	check("the ending words are one function",
		TradePanel.ending_text("x", null, {"trade": {"trade_id": "x"}}) == "Trade complete.")

	# ---- the result reaches whoever accepted first ----
	var saved_slots: Array = CharacterData.character_slots.duplicate(true)
	var saved_index: int = CharacterData.active_character_index
	var announced: Array = []
	var listen := func(resync: Dictionary) -> void: announced.append(resync)
	CharacterData.carry_adopted.connect(listen)

	var cells: Array = []
	cells.resize(30)
	cells[4] = {"item_id": "ironsword", "quantity": 1.0}
	CharacterData.character_slots = [{"gold": 10, "inventory": []}, null, {"gold": 900, "inventory": []}, null]
	CharacterData.active_character_index = 0
	var record: Dictionary = {"trade_id": "t-one", "with": "bob", "with_name": "Bram",
		"got": [{"item_id": "ironsword", "quantity": 1}], "gave": [], "gold_got": 0,
		"gold_gave": 300, "tax": 10, "at": 1}

	panel._apply_poll({"trade": _trade_payload(1, sword), "resync": null})
	panel._apply_poll({"trade": null, "last": null,
		"resync": {"slot": 2, "gold": 610, "inventory": cells, "trade": record}})
	var slot2: Dictionary = CharacterData.character_slots[2]
	check("the trade poll's result lands in that character's saved copy",
		int(slot2.get("gold", -1)) == 610 and slot2.get("inventory", []).size() == 30, slot2.get("gold"))
	# NULL-SAFE: a sabotage that leaves the cache alone must fail THIS check,
	# not index an empty array and unwind the rest of the section.
	var cached: Array = slot2.get("inventory", []) if slot2.get("inventory", []) is Array else []
	var fourth: Variant = cached[4] if cached.size() > 4 else null
	check("with the quantities as integers, not JSON's floats",
		fourth is Dictionary and typeof((fourth as Dictionary).get("quantity")) == TYPE_INT, fourth)
	check("and the window says complete from it", panel.notice_label.text == "Trade complete.")
	check("it is announced once", announced.size() == 1, announced.size())

	# The live character: a stand-in player with a purse and a cached bag.
	var fake := GDScript.new()
	fake.source_code = "extends Node\nvar gold: int = 0\nvar inventory_data: Array = []\n" \
		+ "func set_gold(v: int) -> void:\n\tgold = v\n"
	fake.reload()
	var body: Node = Node.new()
	body.set_script(fake)
	check("apply_server_carry() adopts onto the character being played",
		CharacterData.apply_server_carry({"slot": 0, "gold": 42, "inventory": cells, "trade": record}, body))
	check("its purse is the server's number", int(body.gold) == 42, body.gold)
	var carried: Array = body.inventory_data
	check("and the bag its next save will send is the server's bag",
		carried.size() == 30 and carried[4] is Dictionary and (carried[4] as Dictionary).get("item_id") == "ironsword")
	check("so that save no longer deletes what the trade gave",
		int((CharacterData.character_slots[0] as Dictionary).get("gold", -1)) == 42)
	var before: int = announced.size()
	check("an empty array is not an empty bag - it is ignored",
		not CharacterData.apply_server_carry({"slot": 0, "gold": 1, "inventory": []}, body)
		and int(body.gold) == 42)
	check("nor is a slot that is not there", not CharacterData.apply_server_carry(
		{"slot": 9, "gold": 1, "inventory": cells}, body))
	check("nor anything that is not a result", not CharacterData.apply_server_carry("nope", body))
	check("and none of those announced anything", announced.size() == before, announced.size())

	# THE SAVE PATH HAS NOTHING TO ADOPT ANY MORE. A save used to carry the
	# whole bag, and a 409 from a trade that had run meanwhile came back with
	# the server's bag for _adopt_refusal() to take. The bag is the server's
	# now (ONE CELL AT A TIME): a save carries no bag, and a trade's result
	# reaches this client only through apply_server_carry() above, from the
	# trade poll or the broadcast poll. These checks named the old function
	# after it was gone, and the SCRIPT ERROR that made silently ended this
	# section there - every check below it went unrun and still read 0 failed.
	var storage := ServerStorage.new()
	check("the save path has no whole-bag refusal to adopt - a trade's bag comes on the poll",
		not storage.has_method("_adopt_refusal"))
	var ss_src: String = _code_only(FileAccess.get_file_as_string("res://src/systems/serverstorage.gd"))
	check("and a save never names the bag routes",
		not ss_src.contains("/api/character/inventory\"") and not ss_src.contains("/api/account/bank\""))
	body.free()

	# ---- history ----
	panel._apply_recent({"trades": [record], "now": 3601})
	var recent_texts: Array = _guild_texts(panel.recent_list)
	# THE ITEM'S NAME AS THE REGISTRY HAS IT - "Iron Sword" with the art pack
	# present, its id without (a .tres naming missing art does not load). The
	# sentence is what is under test, not the pack.
	var sword_name: String = TradePanel.item_name("ironsword")
	var potion_name: String = TradePanel.item_name("tinyhealthpotion")
	check("recent trades are listed from your side",
		recent_texts.size() >= 1 and str(recent_texts[0]) == "Bram: got %s for 300 gold" % sword_name, recent_texts)
	check("aged against the server's clock", recent_texts.has("1 h ago"), recent_texts)
	var first_row: Control = panel.recent_list.get_child(0) as Control if panel.recent_list.get_child_count() > 0 else Control.new()
	check("and the whole sentence is in the tooltip",
		first_row.tooltip_text == TradePanel.result_line(record), first_row.tooltip_text)
	check("the sentence says what came, what went and the cut",
		TradePanel.result_line(record)
			== "Trade with bob complete: you got %s for 300 gold. The kingdom took 10 gold." % sword_name,
		TradePanel.result_line(record))
	var gift: Dictionary = {"with": "bob", "got": [], "gave": [], "gold_got": 1500, "gold_gave": 0, "tax": 75}
	check("a gift reads as a gift, not a trade 'for nothing'",
		TradePanel.result_line(gift) == "Trade with bob complete: you got 1,500 gold. The kingdom took 75 gold."
		and TradePanel.history_line(gift) == "bob: got 1,500 gold", [TradePanel.result_line(gift), TradePanel.history_line(gift)])
	check("and one you gave away reads that way round",
		TradePanel.history_line({"with": "bob", "gave": [], "gold_gave": 20, "got": []}) == "bob: gave 20 gold")
	var stacked := ItemData.new()
	stacked.value = 50
	stacked.stackable = true
	var single := ItemData.new()
	single.value = 16000
	single.stackable = false
	check("'each' only where there can be more than one",
		TradePanel.value_hint(stacked) == "50 gold each" and TradePanel.value_hint(single) == "worth 16,000 gold",
		[TradePanel.value_hint(stacked), TradePanel.value_hint(single)])
	check("big numbers are grouped, as the backpack groups them",
		TradePanel.worth_text(40500) == "worth 40,500 gold"
		and TradePanel.summary_text({"tax": 2025}, {"offering_value": 40500})
			== "You receive 40,500 gold's worth. The kingdom takes 2,025 gold from you.")
	var listed: String = TradePanel.goods_text([{"item_id": "ironsword", "quantity": 1},
		{"item_id": "tinyhealthpotion", "quantity": 3}], 20)
	check("lists read as lists",
		listed == "%s, 3 x %s and 20 gold" % [sword_name, potion_name], listed)
	# A PET, because the pets are the items whose art is not in the private pack
	# - so this one is meaningful on a clone without it, where the sword is not.
	check("an item the registry knows is called by its name, not its id",
		TradePanel.item_name("petboss") == "Crowned Companion", TradePanel.item_name("petboss"))
	check("and one it does not know falls back to its id rather than to nothing",
		TradePanel.item_name("nosuchthing") == "nosuchthing")
	panel._apply_recent({"trades": [], "now": 1})
	check("no trades yet says so", " ".join(_guild_texts(panel.recent_list)).contains("None yet"))

	# ---- nearby, drawn like every other list ----
	panel._apply_nearby({"area": "town", "precision": "area", "players": [
		{"username": "bob", "slot": 1, "name": "Bram", "level": 7, "role": "mod", "name_hue": 200}]})
	var nearby_row: Node = panel.nearby_list.get_child(0) if panel.nearby_list.get_child_count() > 0 else Node.new()
	var nearby_name: Label = nearby_row.get_node_or_null("name") as Label
	check("a nearby player's character is drawn in their colour with their badge",
		nearby_name != null and nearby_name.text == "Bram"
		and nearby_name.get_theme_color("font_color") == NameTag.colour(200)
		and nearby_row.get_node_or_null("badge") != null)
	check("with a Trade button", nearby_row.get_node_or_null("tradewith") is Button)

	CharacterData.carry_adopted.disconnect(listen)
	CharacterData.character_slots = saved_slots
	CharacterData.active_character_index = saved_index
	panel.queue_free()
	Api.username = was_name

	# ---- the HUD: the person asked is told ----
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	hud._build_status_strip()
	var trade_button: Button = hud.get_node_or_null("%tradebutton") as Button
	check("the HUD has its Trade button", trade_button != null)
	check("the poll tells the server which character this is",
		hud._broadcast_path().ends_with("&slot=%d" % CharacterData.active_character_index), hud._broadcast_path())
	var asked: Dictionary = {"trade_id": "t-9", "with": "bob", "from_them": true,
		"they_accepted": false, "you_accepted": false}
	hud._read_trade(asked)
	check("a trade opened with you lights the strip",
		hud.status_strip.visible and hud.status_label.text == "bob wants to trade with you", hud.status_label.text)
	check("and the Trade button", trade_button != null and trade_button.text == "Trade •")
	var said: int = hud.message_rows.get_child_count()
	check("and says so once", said == 1, said)
	hud._read_trade(asked)
	check("not again on the next poll", hud.message_rows.get_child_count() == said)
	hud._read_trade({"trade_id": "t-9", "with": "bob", "from_them": true,
		"they_accepted": true, "you_accepted": false})
	check("when they accept, the strip says they are waiting on you",
		hud.status_label.text == "bob accepted your trade - waiting on you", hud.status_label.text)
	hud._read_trade({"trade_id": "t-9", "with": "bob", "from_them": true,
		"they_accepted": true, "you_accepted": true})
	check("once you have too, nothing is waiting on you", not hud.status_strip.visible)
	hud.set_world_status("pvp", "PvP is ON")
	hud._read_trade(asked)
	check("a waiting trade outranks the pvp notice on the strip",
		hud.status_label.text == "bob wants to trade with you", hud.status_label.text)
	hud._read_trade(null)
	check("when it is answered the light goes out",
		hud.status_label.text == "PvP is ON" and trade_button != null and trade_button.text == "Trade")
	hud._read_trade({"trade_id": "t-10", "with": "bob", "from_them": false,
		"they_accepted": false, "you_accepted": false})
	check("a trade you opened is not announced to you", hud.message_rows.get_child_count() == said
		and hud.status_label.text == "PvP is ON")

	var saved_slots2: Array = CharacterData.character_slots.duplicate(true)
	CharacterData.character_slots = [null, null, {"gold": 0, "inventory": []}, null]
	hud._on_carry_adopted({"trade": record})
	var last_line: Node = hud.message_rows.get_child(hud.message_rows.get_child_count() - 1)
	check("a finished trade is announced in the sentence the history uses",
		" ".join(_guild_texts_any(last_line)).contains(TradePanel.result_line(record)))
	hud._read_trade_resync({"slot": 2, "gold": 77, "inventory": cells})
	check("the broadcast poll's result lands too",
		int((CharacterData.character_slots[2] as Dictionary).get("gold", -1)) == 77)

	# THE POLL ITSELF, with an answer in the shape the server sends - so a
	# reader that is never called from it fails here, not in a player's hands.
	hud._read_trade(null)
	hud._apply_broadcast({"messages": [], "latest_id": 0, "maintenance": null, "pvp": false,
		"teleport": null, "guild_tag": "", "trade": {"trade_id": "t-11", "with": "cara",
		"from_them": true, "they_accepted": false, "you_accepted": false},
		"trade_resync": {"slot": 2, "gold": 88, "inventory": cells}})
	check("the broadcast poll lights a waiting trade",
		hud.status_label.text == "cara wants to trade with you", hud.status_label.text)
	check("and hands on a finished one",
		int((CharacterData.character_slots[2] as Dictionary).get("gold", -1)) == 88)
	var toggle_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var toggle_at: int = toggle_src.find("func toggle_trade")
	check("opening the window puts the light out at once, not a poll later",
		_within(toggle_src.find('set_world_status("trade", "")', toggle_at),
			toggle_src.find("toggle_panel(", toggle_at)) != -1)

	# WIRED WHERE THE POLL STARTS, so a result delivered by ANY route is
	# announced - the window's poll and the save path do not know the HUD.
	# The HUD is out of the tree, so its timer never runs; the deferred first
	# poll finds nobody logged in and returns.
	hud._start_broadcast_poll()
	check("the HUD listens for a result however it arrived",
		CharacterData.carry_adopted.is_connected(hud._on_carry_adopted))
	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var start_at: int = hud_src.find("func _start_broadcast_poll")
	check("and polls once on arrival rather than ten seconds later - the poll is how the server learns the slot",
		_within(hud_src.find("_on_broadcast_poll_timeout.call_deferred()", start_at),
			hud_src.find("\nfunc ", start_at + 10)) != -1)
	await get_tree().process_frame
	if CharacterData.carry_adopted.is_connected(hud._on_carry_adopted):
		CharacterData.carry_adopted.disconnect(hud._on_carry_adopted)
	CharacterData.character_slots = saved_slots2
	hud.free()


func _guild_texts_any(node: Node) -> Array:
	# Like _guild_texts(), for a node that is not in the tree.
	var out: Array = []
	if node is Label or node is RichTextLabel:
		out.append(node.get_parsed_text() if node is RichTextLabel else str(node.text))
	for child in node.find_children("*", "", true, false):
		if child is Label:
			out.append(str(child.text))
		elif child is RichTextLabel:
			out.append((child as RichTextLabel).get_parsed_text())
	return out


# =============================================================================
# GUILD CHAT — the tab asks the server, and shows what it says
# =============================================================================
# Reported with a screenshot: the Guild tab said "Guilds are not in the game
# yet." and "oi bruv" went nowhere. Guilds had been in the game for weeks and
# the SERVER had guild chat - send, read, and the "are you in one" check, all
# tested in test_guilds.py and test_chatrooms.py. The client refused in four
# places without asking: opening the tab, the poll, Say, and the picture
# button. The same finished-half-with-nothing-joined-to-it as the staff desk.

func _test_guild_chat_is_open() -> void:
	section("GUILD CHAT — the tab asks the server, and shows what it says")

	var packed: PackedScene = load("res://scene/ui/chat/chatpanel.tscn") as PackedScene
	check("chatpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var chat: Control = packed.instantiate() as Control
	add_child(chat)
	chat.visible = true
	await get_tree().process_frame

	chat._show_channel("guild")
	check("opening the Guild tab no longer says guilds are not in the game",
		not chat.notice.text.contains("not in the game"), chat.notice.text)
	check("the poll asks the server for guild chat",
		chat._poll_path() == "/api/chat?channel=guild&since=0", chat._poll_path())
	check("nothing refuses guild on this side - the server knows if you are in one",
		chat._local_refusal("guild") == "")
	chat._whisper_with = ""
	check("a whisper to nobody is still the one local refusal",
		chat._local_refusal("private").begins_with("Type who you want to whisper to"))
	check("and the poll does not ask for it", (func() -> String:
		chat._channel = "private"
		var asked: String = chat._poll_path()
		chat._channel = "guild"
		return asked).call() == "")

	# ---- a guild line arrives ----
	var now: int = int(Time.get_unix_time_from_system())
	chat._apply_read("guild", {"channel": "guild", "available": true, "latest_id": 5, "removed": [],
		"messages": [{"id": 5, "by": "rowdy", "role": "player", "name_hue": 120,
			"guild_tag": "THE FIRST", "body": "oi bruv", "at": now}]})
	await get_tree().process_frame
	var lines: Array = chat._feeds["guild"]["lines"]
	check("a guild line from the server lands in the guild feed",
		lines.size() == 1 and str((lines[0] as Dictionary).get("body", "")) == "oi bruv", lines)
	check("and moves the guild cursor", int(chat._feeds["guild"]["cursor"]) == 5)
	var shown: Array = []
	for child in chat.lines_box.get_children():
		for text_node in [child] + child.find_children("*", "RichTextLabel", true, false):
			if text_node is RichTextLabel:
				shown.append((text_node as RichTextLabel).get_parsed_text())
	check("and is drawn on the Guild tab, tag and all",
		" ".join(shown).contains("rowdy: oi bruv") and " ".join(shown).contains("THE FIRST"), shown)

	# ---- not in a guild: the server's words, not a guess ----
	var told: String = "You are not in a guild yet. Open Guild to found one, or answer an invite."
	chat._apply_read("guild", {"channel": "guild", "available": false, "notice": told,
		"messages": [], "removed": [], "latest_id": 0})
	check("not in a guild shows what the server said", chat.notice.text == told, chat.notice.text)
	check("and a player removed from a guild stops seeing its last page",
		(chat._feeds["guild"]["lines"] as Array).is_empty())
	# WHILE THE ROOM IS SHUT a send is tried and refused - a different notice
	# now stands. The room opening must take down ITS notice and only that.
	chat._set_notice("That was refused for another reason.")
	chat._apply_read("guild", {"channel": "guild", "available": true, "latest_id": 6, "removed": [],
		"messages": []})
	check("a refusal from a send is not wiped when the room opens",
		chat.notice.text == "That was refused for another reason.", chat.notice.text)
	chat._apply_read("guild", {"channel": "guild", "available": false, "notice": told,
		"messages": [], "removed": [], "latest_id": 0})
	chat._apply_read("guild", {"channel": "guild", "available": true, "latest_id": 6, "removed": [],
		"messages": []})
	check("but the room's own notice comes down when you join", chat.notice.text == "", chat.notice.text)

	# ---- Say and the picture button go through the same gate ----
	var chat_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/chat/chatpanel.gd"))
	check("no code path says guilds are not in the game any more",
		not chat_src.contains('_set_notice("Guilds are not in the game yet.")'))
	var say_at: int = chat_src.find("func _on_send_pressed")
	var say_end: int = chat_src.find("\nfunc ", say_at + 10)
	check("Say asks _local_refusal() and then sends to the open channel, guild included",
		_within(chat_src.find("_local_refusal(_channel)", say_at), say_end) != -1
		and _within(chat_src.find("await _send(_channel, text, \"\")", say_at), say_end) != -1)
	var pic_at: int = chat_src.find("func _postable_channel")
	check("and so does the picture button",
		_within(chat_src.find("_local_refusal(_channel)", pic_at), chat_src.find("\nfunc ", pic_at + 10)) != -1)
	var poll_at: int = chat_src.find("func _poll()")
	check("and the poll hands every answer to _apply_read()",
		_within(chat_src.find("_apply_read(asked, data)", poll_at), chat_src.find("\nfunc ", poll_at + 10)) != -1)

	chat.queue_free()


# =============================================================================
# STAFF DESK — TRADES: "he scammed me", checked from the desk
# =============================================================================
# Every finished trade is kept so a report can be checked, and until now the
# only way to check one was sqlite3 on the server. The server half is
# test_trades.py (T-12): reach, paging by a pair cursor, the tally. These are
# the desk's half, driven with pages in the shape the server sends.

func _staff_trade(state: String, at: int) -> Dictionary:
	return {"trade_id": "abcdef1234567890", "state": state, "at": at, "opened_at": at - 60,
		"character": "Aldra", "with": "rowdy", "with_name": "Rowan",
		"gave": [{"item_id": "petboss", "quantity": 1}], "got": [], "gold_gave": 0,
		"gold_got": 1500, "tax": 75 if state == "done" else 0}


func _test_the_staff_desk_reads_trades() -> void:
	section("STAFF DESK — TRADES: what an account gave, got and paid, one page at a time")

	var packed: PackedScene = load("res://scene/ui/staff/staffpanel.tscn") as PackedScene
	check("staffpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var StaffPanel: Script = load("res://src/ui/staff/staffpanel.gd") as Script
	var was_role: String = Api.role
	Api.role = "mod"
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	panel._log_loaded = true
	await get_tree().process_frame
	panel._selected = "alice"
	panel._selected_entry = {"username": "alice", "role": "player", "actionable": true}
	panel._show_detail(panel._selected_entry)

	check("the Trades tab is the third tab", panel.detail_tabs.get_tab_title(panel.TRADES_TAB) == "Trades")

	# ---- a page ----
	var now: int = 1_790_000_000
	panel._apply_trades_page({"ok": true, "status": 200, "data": {
		"username": "alice", "more": true, "next_before": {"at": 1789990000.0, "seq": 42.0},
		"summary": {"done": 17, "cancelled": 13, "open": 1}, "now": now,
		"trades": [_staff_trade("done", now - 100), _staff_trade("cancelled", now - 200),
			_staff_trade("open", now - 300)]}}, "fresh", "alice")
	await get_tree().process_frame
	var rows: Array = panel.trade_list.get_children()
	check("each trade is a row", rows.size() == 3, rows.size())
	var first: Label = rows[0] as Label if rows.size() > 0 else Label.new()
	var pet: String = _trade_panel_script().item_name("petboss")
	check("a finished trade reads from the account's side, with whom and on which character",
		first.text.ends_with("with Rowan (rowdy), as Aldra: got 1,500 gold for %s. The kingdom took 75 gold." % pet),
		first.text)
	check("in the same words the player's own history uses",
		first.text.contains(_trade_panel_script().exchange_text(_staff_trade("done", now))))
	var second: Label = rows[1] as Label if rows.size() > 1 else Label.new()
	check("a called-off one says so, and what it would have done",
		second.text.contains("called off (it would have got 1,500 gold for %s)" % pet), second.text)
	var third: Label = rows[2] as Label if rows.size() > 2 else Label.new()
	check("an open one says so - a scam is often reported mid-attempt",
		third.text.contains("still open (so far it would get 1,500 gold for %s)" % pet), third.text)
	check("finished, called off and open are told apart by colour too",
		first.get_theme_color("font_color") != second.get_theme_color("font_color")
		and third.get_theme_color("font_color") != first.get_theme_color("font_color"))
	check("the tally comes first", panel.trade_summary.text == "Trades: 17 finished · 13 called off · 1 open",
		panel.trade_summary.text)
	check("and on the tab", panel.detail_tabs.get_tab_title(panel.TRADES_TAB) == "Trades (17)",
		panel.detail_tabs.get_tab_title(panel.TRADES_TAB))
	check("the tooltip carries the trade id the ledger names, and the other person",
		first.tooltip_text.contains("Trade abcdef12") and first.tooltip_text.contains("Click to open rowdy"),
		first.tooltip_text)
	check("and the row opens them", first.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND
		and first.gui_input.get_connections().size() == 1)

	# ---- paging by the pair cursor ----
	check("Older trades is offered", panel.trade_more.visible)
	var asked: Dictionary = panel._trades_params("more")
	check("and asks for the page after (at, seq) - JSON's floats made whole",
		asked.get("before_at") == 1789990000 and asked.get("before_seq") == 42
		and asked.get("username") == "alice", asked)
	panel._apply_trades_page({"ok": true, "status": 200, "data": {"more": false, "next_before": null,
		"summary": {"done": 17}, "now": now, "trades": [_staff_trade("done", now - 400)]}}, "more", "alice")
	check("the next page is added below, not in place", panel.trade_list.get_child_count() == 4)
	check("and the last page takes the button away", not panel.trade_more.visible
		and panel._trades_params("more").is_empty())
	panel._apply_trades_page({"ok": true, "status": 200, "data": {"more": true, "next_before": null,
		"summary": {}, "now": now, "trades": []}}, "fresh", "alice")
	check("'more' with no cursor is not believed", not panel.trade_more.visible)
	check("an empty history says so", panel.trade_empty.visible
		and panel.trade_empty.text == "alice has not traded with anybody.", panel.trade_empty.text)
	check("the cursor reader refuses nothing-shaped cursors",
		StaffPanel.trade_cursor({"next_before": null}).is_empty()
		and StaffPanel.trade_cursor({"next_before": {"at": 0, "seq": 5}}).is_empty()
		and StaffPanel.trade_cursor({}).is_empty())

	# ---- out of reach reads like no account ----
	panel._apply_trades_page({"ok": false, "status": 404, "error": "No such account."}, "fresh", "alice")
	check("out of reach is said plainly", panel.trade_empty.text == "You cannot read this account's trades.",
		panel.trade_empty.text)

	# ---- the tab loads itself, and a new pick forgets the old ----
	panel._trades_for = ""
	panel.detail_tabs.current_tab = panel.TRADES_TAB
	# READ AT ONCE, not a frame later. _load_trades() writes this line before
	# its first await; a frame is long enough for a refused connection to come
	# back and write "Could not read trades" over it, which is how this check
	# failed on a machine with nothing listening on the port.
	check("opening the Trades tab asks for that account's trades",
		panel.trade_empty.text == "Reading alice's trades...", panel.trade_empty.text)
	await get_tree().process_frame
	panel._apply_trades_page({"ok": true, "status": 200, "data": {"more": false, "summary": {"done": 2},
		"now": now, "trades": [_staff_trade("done", now)]}}, "fresh", "alice")
	panel._pick("rowdy")
	check("picking somebody else forgets alice's trades at once",
		panel._trades.is_empty() and panel._trades_for == "", panel._trades.size())
	check("and asks for theirs, since the Trades tab is the one open",
		panel.trade_empty.text == "Reading rowdy's trades...", panel.trade_empty.text)
	check("the tab title does not carry alice's count onto rowdy",
		panel.detail_tabs.get_tab_title(panel.TRADES_TAB) == "Trades")

	panel.queue_free()
	Api.role = was_role


func _trade_panel_script() -> Script:
	# The trade window's statics, which the desk borrows its wording from.
	return load("res://src/ui/trade/tradepanel.gd") as Script


# =============================================================================
# FRIENDS — the header: a title, a line in words, and one ×
# =============================================================================
# The header had a boxed "R" beside a boxed "x" in a style nothing else used,
# and said "0 online of 0" to somebody with no friends. It is the guild
# header's shape now; the list re-reads itself, so there is no R.

func _test_the_friends_header_reads_well() -> void:
	section("FRIENDS — a title, a line in words, and one ×")

	var packed: PackedScene = load("res://scene/ui/friends/friendspanel.tscn") as PackedScene
	check("friendspanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var Friends: Script = load("res://src/ui/friends/friendspanel.gd") as Script
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame
	var now: int = 1_790_000_000
	panel._repaint({"now": now,
		"friends": [
			{"username": "rowdy", "role": "player", "online": true, "last_seen_at": now},
			{"username": "quietone", "role": "mod", "online": false, "last_seen_at": now - 7200},
			{"username": "Tunacan", "role": "owner", "online": true, "last_seen_at": now},
			{"username": "p001", "role": "player", "online": false, "last_seen_at": now - 86400 * 5}],
		"incoming": [{"username": "newbie", "role": "player", "online": true, "last_seen_at": now}],
		"outgoing": []})
	await get_tree().process_frame
	await get_tree().process_frame

	var header: Node = panel.get_node("frame/margin/rows/headerpanel")
	var letters: Array = []
	for b in header.find_children("*", "Button", true, false):
		letters.append((b as Button).text)
	check("the header has one button, the same × as every other panel", letters == ["×"], letters)
	check("and no R: the list re-reads itself", panel.get_node_or_null("%friendsrefreshbutton") == null)
	check("the × is flat, like the guild's and the trade window's",
		(panel.close_button as Button).flat)
	check("the line under the title is words", panel.count_label.text == "2 of 4 friends online",
		panel.count_label.text)
	check("a request waiting is said in the header too",
		panel.requests_label.visible and panel.requests_label.text == "· 1 request waiting",
		panel.requests_label.text)
	var fits := func(label: Label) -> bool:
		var need: float = label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		return label.size.x + 0.5 >= need
	check("both fit, whole", fits.call(panel.count_label) and fits.call(panel.requests_label),
		[panel.count_label.size.x, panel.requests_label.size.x])

	panel._repaint({"now": now, "friends": [], "incoming": [], "outgoing": []})
	check("nobody yet is said in words, not '0 online of 0'",
		panel.count_label.text == "nobody on your list yet" and not panel.requests_label.visible,
		panel.count_label.text)
	var one_on: Array = [{"online": true}]
	var one_off: Array = [{"online": false}]
	check("one friend reads as one", Friends.header_line(one_on) == "1 friend, online"
		and Friends.header_line(one_off) == "1 friend, offline")
	check("everybody on, nobody on",
		Friends.header_line([{"online": true}, {"online": true}]) == "2 friends, all online"
		and Friends.header_line([{"online": false}, {"online": false}]) == "2 friends, none online")
	check("more than one request", Friends.requests_text(3) == "· 3 requests waiting"
		and Friends.requests_text(0) == "")

	panel.close_button.emit_signal("pressed")
	check("the × closes it", not panel.visible)
	panel.queue_free()



# =============================================================================
# THE LOGIN SCREEN DOES NOT WAIT FOR THE WORLD
# =============================================================================
# characterselect.gd used to preload elusion.tscn, and loginmenu.tscn exports
# characterselect.tscn, so the login screen's first frame waited on the town,
# the field it exports, the HUD, every panel and about sixty scripts. Measured
# cold in the sandbox: a login box at 2.6 s, 1.8 s of it the world. Now the
# town loads on a worker thread while the player types (AreaRegistry.prefetch)
# and the login box is up in under a second.
#
# THE WALK IS THE CHECK. A preload is invisible to get_dependencies(), which is
# exactly how this chain went unnoticed: nothing in the scene file named the
# town. So the walk reads the preloads out of every script it passes through.

func _load_closure(root_path: String) -> Dictionary:
	"""Every resource loading `root_path` pulls in: path -> the path that pulled
	it, so a failure can print the chain."""
	var seen: Dictionary = {root_path: ""}
	var todo: Array = [root_path]
	var preload_rx := RegEx.create_from_string("preload\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
	while not todo.is_empty():
		var path: String = todo.pop_back()
		var found: Array = []
		for dep in ResourceLoader.get_dependencies(path):
			var parts: PackedStringArray = str(dep).split("::")
			var dep_path: String = parts[parts.size() - 1]
			if dep_path.begins_with("uid://"):
				dep_path = ResourceUID.get_id_path(ResourceUID.text_to_id(dep_path))
			found.append(dep_path)
		if path.ends_with(".gd"):
			for m in preload_rx.search_all(_code_only(FileAccess.get_file_as_string(path))):
				found.append(m.get_string(1))
		for dep_path in found:
			if not seen.has(dep_path):
				seen[dep_path] = path
				todo.append(dep_path)
	return seen


func _chain(closure: Dictionary, path: String) -> String:
	var links: Array = [path]
	var at: String = path
	while closure.get(at, "") != "":
		at = closure[at]
		links.push_front(at.get_file())
	return " -> ".join(links)


func _test_the_world_loads_in_the_background() -> void:
	section("LOADING — the login screen does not wait for the world")

	var areas: Dictionary = AreaRegistry.AREAS
	var login := _load_closure("res://scene/ui/menus/loginmenu.tscn")
	check("the walk reaches character select's script (it is not blind)",
		login.has("res://src/ui/menus/characterselect.gd"), login.keys().size())
	var town_walk := _load_closure(areas["elusion"])
	check("and it follows an exported scene: the town pulls the field",
		town_walk.has(areas["field"]))
	var hud_walk := _load_closure("res://src/ui/characterhud.gd")
	check("and a script's preloads: the HUD pulls the trade window",
		hud_walk.has("res://scene/ui/trade/tradepanel.tscn"))
	var pulled: Array = []
	for area_id in areas:
		if login.has(areas[area_id]):
			pulled.append(_chain(login, areas[area_id]))
	check("the login screen's load pulls in no area", pulled.is_empty(), pulled)

	var world: PackedScene = load(areas["elusion"]) as PackedScene
	check("the town still loads - what the preload used to promise",
		world != null and world.can_instantiate())

	# ---- who asks for it -------------------------------------------------
	var Select: Script = load("res://src/ui/menus/characterselect.gd") as Script
	var world_area: String = str(Select.get_script_constant_map().get("WORLD_AREA", ""))
	check("character select names the area it starts in, and it is an area",
		areas.has(world_area), world_area)
	var login_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/menus/loginmenu.gd"))
	var ready_at: int = login_src.find("func _ready()")
	var ready_end: int = login_src.find("\nfunc ", ready_at + 1)
	check("the login screen starts that area loading as it opens",
		_within(login_src.find("AreaRegistry.prefetch(\"%s\")" % world_area, ready_at), ready_end) != -1)
	var select_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/menus/characterselect.gd"))
	var enter_at: int = select_src.find("func _enter_world(")
	var enter_end: int = select_src.find("\nfunc ", enter_at + 1)
	check("picking a character takes the town from the registry",
		_within(select_src.find("AreaRegistry.scene_for(WORLD_AREA)", enter_at), enter_end) != -1)
	check("and queues the other areas behind it",
		_within(select_src.find("AreaRegistry.prefetch_all()", enter_at), enter_end) != -1)
	var pick_at: int = select_src.find("func _select_character(")
	check("a second click cannot change the character mid-load",
		select_src.find("if _entering", pick_at) != -1
		and select_src.find("if _entering", pick_at) < select_src.find("active_character_index = idx", pick_at))

	# Forget the town first, or a town already held would pass this for free.
	var settle_first: int = Time.get_ticks_msec() + 20000
	while AreaRegistry.is_loading(world_area) and Time.get_ticks_msec() < settle_first:
		await get_tree().process_frame
	AreaRegistry._cache.erase(world_area)
	var screen_packed: PackedScene = load("res://scene/ui/menus/characterselect.tscn") as PackedScene
	var screen: Control = screen_packed.instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	check("character select asks for the town too (arriving from the world)",
		AreaRegistry.is_loading(world_area) or AreaRegistry._cache.has(world_area))
	screen._show_loading(2)
	var locked: bool = true
	for b in screen.find_children("*", "Button", true, false):
		if str(b.name).begins_with("selectbutton") or str(b.name).begins_with("createbutton"):
			locked = locked and (b as Button).disabled
	check("while it finishes the screen says so, and every slot button waits",
		screen.get_node("%label3").text == "Loading the world..." and locked,
		screen.get_node("%label3").text)
	screen.queue_free()

	# ---- the registry --------------------------------------------------------
	check("an area that does not exist is refused", not AreaRegistry.prefetch("nowhere"))
	# Settle whatever the screen above started, then forget two areas so the
	# loader has real work.
	var settle_until: int = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < settle_until:
		await get_tree().process_frame
	AreaRegistry._cache.erase("boss")
	AreaRegistry._cache.erase("bossarena")
	AreaRegistry._cache.erase("easteregg")
	var to_load: int = 0
	for area_id in areas:
		if not AreaRegistry._cache.has(area_id):
			to_load += 1
	AreaRegistry.prefetch_all()
	check("prefetch_all() starts one load and queues the rest",
		to_load >= 3 and AreaRegistry._prefetching.size() == 1
		and AreaRegistry._prefetch_queue.size() == to_load - 1,
		[to_load, AreaRegistry._prefetching.keys(), AreaRegistry._prefetch_queue])
	check("and the registry is watching for it", AreaRegistry.is_processing())
	var most_at_once: int = 0
	var until: int = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < until:
		most_at_once = maxi(most_at_once, AreaRegistry._prefetching.size())
		await get_tree().process_frame
	check("one at a time, all the way through", most_at_once == 1, most_at_once)
	var all_held: bool = true
	var same_object: bool = true
	for area_id in areas:
		all_held = all_held and AreaRegistry._cache.get(area_id) is PackedScene
		same_object = same_object and load(areas[area_id]) == AreaRegistry._cache.get(area_id)
	check("every area ends up held", all_held, AreaRegistry._cache.keys())
	check("and a door's load() gets the very scene the loader made", same_object)
	check("the registry stops watching once there is nothing to collect",
		not AreaRegistry.is_processing())

	# The door is reached before the loader is done: scene_for() waits for it
	# rather than loading it a second time.
	AreaRegistry._cache.erase("bossarena")
	AreaRegistry.prefetch("bossarena")
	var early: PackedScene = AreaRegistry.scene_for("bossarena")
	check("an area asked for mid-load comes back whole",
		early != null and early.can_instantiate() and AreaRegistry._cache.get("bossarena") == early
		and not AreaRegistry.is_loading("bossarena"))

	# An area still waiting its turn is loaded on the spot and leaves the queue.
	AreaRegistry._cache.erase("boss")
	AreaRegistry._cache.erase("easteregg")
	AreaRegistry.prefetch("boss")
	AreaRegistry.prefetch("easteregg")
	var queued_now: bool = AreaRegistry._prefetch_queue.has("easteregg")
	var jumped: PackedScene = AreaRegistry.scene_for("easteregg")
	check("an area still queued is loaded when asked for, and leaves the queue",
		queued_now and jumped != null and not AreaRegistry._prefetch_queue.has("easteregg"),
		[queued_now, AreaRegistry._prefetch_queue])

	# Landing a teleport used to switch the registry's _process() off. With a
	# load still running that would strand it: finished, never collected.
	var stand_in := Node2D.new()
	stand_in.add_to_group("player")
	add_child(stand_in)
	AreaRegistry._arm_spawn(Vector2(12, 34))
	AreaRegistry._apply_spawn_now()
	check("a teleport landing does not stop a load being collected",
		stand_in.global_position == Vector2(12, 34) and not AreaRegistry._has_pending_spawn
		and (AreaRegistry.is_processing() or not AreaRegistry.is_loading("boss")),
		[AreaRegistry.is_processing(), AreaRegistry.is_loading("boss")])
	stand_in.queue_free()
	until = Time.get_ticks_msec() + 20000
	while AreaRegistry.is_loading("boss") and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check("and it is collected", AreaRegistry._cache.get("boss") is PackedScene)

	# ---- the doors -----------------------------------------------------------
	# In Godot 4.6.1 a plain load() of an area that is loading in the background
	# never returns - found when a sabotage of scene_for() hung this suite. The
	# doors that name their destination by path go through scene_at(), which
	# collects the background load instead. A hang cannot be a FAIL line, so the
	# rule is held by reading the code, and scene_at() is held by running it.
	AreaRegistry._cache.erase("bossarena")
	AreaRegistry.prefetch("bossarena")
	var in_flight: bool = AreaRegistry.is_loading("bossarena")
	var through_door: PackedScene = AreaRegistry.scene_at(areas["bossarena"])
	check("a door reached mid-load gets the area, from the registry",
		in_flight and through_door != null and through_door == AreaRegistry._cache.get("bossarena")
		and not AreaRegistry.is_loading("bossarena"))
	var not_an_area: PackedScene = AreaRegistry.scene_at("res://scene/ladderdown.tscn")
	check("and a scene that is not an area still loads the ordinary way",
		not_an_area != null and not AreaRegistry._cache.values().has(not_an_area))

	var area_literals: Array = []
	for area_id in areas:
		area_literals.append("\"%s\"" % areas[area_id])
	var offenders: Array = []
	var dir_stack: Array = ["res://src"]
	while not dir_stack.is_empty():
		var dir_path: String = dir_stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			dir_stack.append(dir_path + "/" + sub)
		for file_name in dir.get_files():
			if not file_name.ends_with(".gd") or file_name in ["testrunner.gd", "arearegistry.gd"]:
				continue
			var code: String = _code_only(FileAccess.get_file_as_string(dir_path + "/" + file_name))
			for call in ["load(", "preload(", "change_scene_to_file(", "load_threaded_request("]:
				var at: int = code.find(call)
				while at != -1:
					var arg: String = code.substr(at + call.length(), 48).split(")")[0].strip_edges()
					if arg in ["destination_scene_path", "world_scene_path"] or area_literals.has(arg):
						offenders.append("%s: %s%s)" % [file_name, call, arg])
					at = code.find(call, at + 1)
	check("no script loads an area by path behind the registry's back", offenders.is_empty(), offenders)
	for door in ["res://src/world/ladder.gd", "res://src/world/victoryteleporter.gd",
			"res://src/ui/menus/gameover.gd"]:
		check("%s goes through AreaRegistry.scene_at()" % door.get_file(),
			_code_only(FileAccess.get_file_as_string(door)).contains("AreaRegistry.scene_at("))

	# Leave nothing loading for the sections after this one.
	until = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < until:
		await get_tree().process_frame


# =============================================================================
# RARE LOOT LOOKS RARE
# =============================================================================
# Nothing marked an item as rare before: an Ember Cuirass sat in a loot bag
# looking exactly like an iron one, and the only "legendary" effect in the game
# was petbeam, a flat Line2D poking 149 pixels out of the sack. Now a tier has a
# name and a colour (GameConstants' RARITY), every slot frames uncommon and up
# in it, the tooltip names it, and a bag on the ground glows for epic or better.
#
# The loot bag panel was also fixed-size - a 200-pixel scroll area under a
# two-item bag - with stack counts at font size 7 and no way to empty it but a
# double-click per cell.

func _rarity_test_item(item_id: String, tier: int, type: int = ItemData.Type.ARMOR) -> ItemData:
	var d := ItemData.new()
	d.item_id = item_id
	d.display_name = "Test %s" % item_id
	d.tier = tier
	d.type = type
	d.max_stack = 99
	d.stackable = true
	return d


func _test_rare_loot_reads_as_rare() -> void:
	section("RARE LOOT — rarity colours, the loot bag, and the glow")

	check("each tier has its name", GameConstants.rarity_name(1) == "Common"
		and GameConstants.rarity_name(2) == "Uncommon" and GameConstants.rarity_name(3) == "Rare"
		and GameConstants.rarity_name(4) == "Epic" and GameConstants.rarity_name(5) == "Legendary",
		[GameConstants.rarity_name(1), GameConstants.rarity_name(5)])
	check("past the end is Mythic, before the start is Common",
		GameConstants.rarity_name(8) == "Mythic" and GameConstants.rarity_name(0) == "Common")
	var seen_colours: Dictionary = {}
	for t in range(1, 7):
		seen_colours[GameConstants.rarity_colour(t).to_html()] = t
	check("the six rarities are six different colours", seen_colours.size() == 6, seen_colours)

	# Items the suite can build without the art pack: the ones a clone has
	# are pets, and the point here is the TIER, not the art.
	var legendary := _rarity_test_item("raritytest_legendary", 5)
	var epic := _rarity_test_item("raritytest_epic", 4)
	var common := _rarity_test_item("raritytest_common", 1)
	var coin := _rarity_test_item("raritytest_coin", 6, ItemData.Type.CURRENCY)
	for d in [legendary, epic, common, coin]:
		ItemRegistry._items[d.item_id] = d

	# ---- the slot -----------------------------------------------------------
	var slot_packed: PackedScene = load("res://scene/ui/inventory/inventoryslot.tscn")
	var slot: InventorySlot = slot_packed.instantiate()
	add_child(slot)
	await get_tree().process_frame
	slot.set_stack(ItemStack.new(legendary, 3))
	var frame: Panel = slot.get_node_or_null("rarityframe")
	check("a legendary item frames its slot in the legendary colour",
		frame != null and frame.visible
		and (frame.get_theme_stylebox("panel") as StyleBoxFlat).border_color == GameConstants.rarity_colour(5))
	check("and the frame sits under the stack count, so the number stays on top",
		frame != null and frame.get_index() < slot.quantity_label.get_index())
	slot.set_stack(ItemStack.new(common, 1))
	check("a common item draws no frame", frame != null and not frame.visible)
	slot.clear_stack()
	check("nor does an empty slot", frame != null and not frame.visible)
	check("the stack count is big enough to read (was font size 7)",
		slot.quantity_label.get_theme_font_size("font_size") >= 10,
		slot.quantity_label.get_theme_font_size("font_size"))
	slot.set_stack(ItemStack.new(epic, 5))
	check("and it shows the count", slot.quantity_label.text == "5", slot.quantity_label.text)
	slot.queue_free()

	# ---- the tooltip ----------------------------------------------------------
	var tip_packed: PackedScene = load("res://scene/ui/inventory/itemtooltip.tscn")
	var tip: Control = tip_packed.instantiate()
	add_child(tip)
	await get_tree().process_frame
	var plain_colour: Color = tip.name_label.get_theme_color("font_color")
	tip.show_for_stack(ItemStack.new(legendary, 1), null)
	check("the tooltip says how rare it is, in its colour",
		tip.rarity_label != null and tip.rarity_label.text == "Legendary"
		and tip.rarity_label.get_theme_color("font_color") == GameConstants.rarity_colour(5),
		tip.rarity_label.text if tip.rarity_label != null else "no label")
	check("and the name takes the colour too",
		tip.name_label.get_theme_color("font_color") == GameConstants.rarity_colour(5))
	tip.show_for_stack(ItemStack.new(common, 1), null)
	check("a common name keeps the tooltip's own gold",
		tip.name_label.get_theme_color("font_color") == plain_colour and tip.rarity_label.text == "Common")
	tip.queue_free()

	# ---- the loot bag panel ---------------------------------------------------
	var Bag: Script = load("res://src/ui/lootbag/lootbaginventory.gd")
	var one := {"item_id": "x", "quantity": 1}
	check("rows: an empty bag is still one row", Bag.rows_needed([], 3) == 1)
	check("rows: two items are one row", Bag.rows_needed([one, one], 3) == 1)
	check("rows: four items are two", Bag.rows_needed([one, one, one, one], 3) == 2)
	check("rows: a gap still counts - the last item decides",
		Bag.rows_needed([null, null, null, one], 3) == 2 and Bag.rows_needed([one, null, null, null], 3) == 1)

	var panel_packed: PackedScene = load("res://scene/ui/lootbag/lootbaginventory.tscn")
	var panel: Control = panel_packed.instantiate()
	add_child(panel)
	await get_tree().process_frame
	var cells: Array = [{"item_id": legendary.item_id, "quantity": 1}, {"item_id": epic.item_id, "quantity": 1}]
	panel._load_contents(cells)
	var shown: int = 0
	for s in panel.loot_container.get_children():
		if s is InventorySlot and s.visible:
			shown += 1
	check("a two-item bag shows one row of cells, not two", shown == 3, shown)
	panel._load_contents(cells + cells)
	shown = 0
	for s in panel.loot_container.get_children():
		if s is InventorySlot and s.visible:
			shown += 1
	check("a four-item bag shows both rows", shown == 6, shown)
	var scroll: Control = panel.get_node("mainpanel/margincontainer/vboxcontainer/lootscroll")
	check("no fixed 200-pixel area under the grid", scroll.custom_minimum_size.y == 0.0,
		scroll.custom_minimum_size)
	check("the cells pack like the inventory's (same -4 spacing)",
		panel.loot_container.get_theme_constant("h_separation") == -4
		and panel.loot_container.get_theme_constant("v_separation") == -4)
	var loot_size: int = int(Bag.get_script_constant_map().get("LOOT_SIZE", 0))
	check("a bag has nine cells, three rows of three (it was six, and boss bags ran past it)",
		loot_size == 9 and panel.loot_container.grid_width * panel.loot_container.grid_height == loot_size,
		[loot_size, panel.loot_container.grid_width, panel.loot_container.grid_height])
	check("there is a Take all button, and it is wired",
		panel.take_all_button != null and panel.take_all_button.pressed.is_connected(panel._on_take_all_pressed))

	# Take all against a pretend server: cell 1 will not fit, the rest do.
	var asked: Array = []
	var answers: Dictionary = {1: {"ok": false, "status": 409}}
	panel._bag_id = "raritytest-bag"
	panel.visible = true
	panel._load_contents(cells + cells)
	panel.take_request = func(_bag: String, cell: int) -> Dictionary:
		asked.append(cell)
		await get_tree().process_frame
		return answers.get(cell, {"ok": true, "data": {"credited": "inventory", "bag_empty": false}})
	var taken: int = await panel.take_all()
	check("Take all asks for every cell, in order", asked == [0, 1, 2, 3], asked)
	check("a cell that will not fit is skipped, not the end of it", taken == 3, taken)
	check("and the ones taken are gone from the grid",
		panel.loot_container.get_children()[0].is_empty() and not panel.loot_container.get_children()[1].is_empty())

	# MUTATED, NOT REASSIGNED: a GDScript lambda captures its locals by value
	# when it is made, so a new dictionary here would never reach it.
	asked.clear()
	answers.clear()
	answers[1] = {"ok": false, "status": 0}
	panel._load_contents(cells + cells)
	taken = await panel.take_all()
	check("a lost connection stops Take all where it failed", asked == [0, 1] and taken == 1, [asked, taken])
	check("and the button comes back", not panel.take_all_button.disabled)
	panel.take_request = Callable()
	panel.queue_free()

	# ---- the bag on the ground ------------------------------------------------
	var World: Script = load("res://src/world/lootbag.gd")
	check("the rarest item sets the bag's tier",
		World.rare_tier_of([{"item_id": common.item_id}, {"item_id": epic.item_id}], false) == 4)
	check("coins do not count, however big the heap",
		World.rare_tier_of([{"item_id": coin.item_id}], false) == 0)
	check("a pet counts as legendary", World.rare_tier_of([], true) == 5)

	var bag_packed: PackedScene = load("res://scene/interactables/lootbag.tscn")
	var bag: Node2D = bag_packed.instantiate()
	add_child(bag)
	await get_tree().process_frame
	check("the old flat beam is gone", bag.get_node_or_null("petbeam") == null)
	bag.set_contents([{"item_id": common.item_id, "quantity": 1}])
	check("a common bag does not glow", bag.glow_tier() == 0)
	bag.set_contents([{"item_id": epic.item_id, "quantity": 1}])
	check("an epic bag glows", bag.glow_tier() == 4)
	var pool: Sprite2D = bag.get_node_or_null("rareglow/pool")
	check("in the epic colour",
		pool != null and Color((pool.texture as GradientTexture2D).gradient.get_color(0), 1.0)
		== Color(GameConstants.rarity_colour(4), 1.0))
	bag.set_has_pet(true)
	check("a pet lights it legendary", bag.glow_tier() == 5)
	bag.set_has_pet(false)
	bag.set_contents([null])
	var glow_node: Node2D = bag.get_node_or_null("rareglow")
	check("and it goes out once the rare thing is taken - the light itself, not just the number",
		bag.glow_tier() == 0 and glow_node != null and not glow_node.visible)
	bag.queue_free()

	for d in [legendary, epic, common, coin]:
		ItemRegistry._items.erase(d.item_id)


# =============================================================================
# AMULETS: WHAT WEARING ONE ADDS
# =============================================================================
# Fifteen amulets in four families, and the family is the colour: green is
# health (Vitality), blue is mana (Arcana), crimson is damage (Fury), purple is
# armour (Ward). The plainest icon of a colour is its lowest tier.
#
# THE SERVER HAS TO AGREE, which is most of what can go wrong. max_hp is
# server-derived and the status route clamps hp to it, so a bonus only this
# client knew about would be taken away on every save. test_gearbonus.py holds
# the server half; this holds the client half and the file between them.

const _AMULET_FAMILIES := {
	# family: [the one field it carries, its tiers, its icon number range]
	"vitality": ["bonus_max_hp", [3, 4, 5], [8018, 8020]],
	"arcana": ["bonus_max_mana", [2, 3, 4, 5], [8053, 8056]],
	"fury": ["bonus_damage_percent", [2, 3, 4, 5], [8049, 8052]],
	"ward": ["armor_value", [2, 3, 4, 5], [8021, 8024]],
}
const _AMULET_PREFIX := {2: "lesser", 3: "", 4: "greater", 5: "exalted"}
const _AMULET_LEVEL := {2: 5, 3: 10, 4: 16, 5: 22}


func _tres_fields(path: String) -> Dictionary:
	# The [resource] block of a .tres as plain key/value text, plus the icon's
	# path under "_icon_path". READ AS TEXT because loading the resource would
	# resolve its icon, and a clone without the art pack has none to resolve -
	# the numbers are what is under test, and they are all in the text.
	var out: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var in_resource := false
	for line in file.get_as_text().split("\n"):
		if line.begins_with("[resource]"):
			in_resource = true
			continue
		if not in_resource:
			if line.begins_with("[ext_resource") and line.contains("Texture2D"):
				var at := line.find("path=\"")
				if at >= 0:
					out["_icon_path"] = line.substr(at + 6, line.find("\"", at + 6) - at - 6)
			continue
		if not line.contains(" = "):
			continue
		var key := line.get_slice(" = ", 0)
		out[key] = line.substr(key.length() + 3).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return out


func _amulet_test_item(item_id: String, field: String, amount: int) -> ItemData:
	var d := ItemData.new()
	d.item_id = item_id
	d.display_name = "Test %s" % item_id
	d.type = ItemData.Type.ARMOR
	d.equip_slot = ItemData.EquipSlot.AMULET
	d.tier = 3
	d.set(field, amount)
	return d


func _test_amulets_carry_their_bonus() -> void:
	section("AMULETS — what wearing one adds, and the server counting it")

	# ---- the fifteen, as authored, and as exported --------------------------
	var gd := _load_gamedata()
	var exported: Dictionary = {}
	for row in gd.get("items", []):
		if row is Dictionary:
			exported[str(row.get("item_id", ""))] = row
	var icons_seen: Dictionary = {}
	var authored: Array = []
	for family in _AMULET_FAMILIES:
		var field: String = _AMULET_FAMILIES[family][0]
		var icon_range: Array = _AMULET_FAMILIES[family][2]
		var amounts: Array = []
		for tier in _AMULET_FAMILIES[family][1]:
			var iid: String = "%s%samulet" % [_AMULET_PREFIX[tier], family]
			var f := _tres_fields("res://data/items/amulets/%s.tres" % iid)
			if f.is_empty():
				check("%s is authored" % iid, false, "no data/items/amulets/%s.tres" % iid)
				continue
			authored.append(iid)
			var amount := int(f.get(field, "0"))
			amounts.append(amount)
			check("%s: its id is its file name, it is an amulet, tier %d at level %d" % [iid, tier, _AMULET_LEVEL[tier]],
				f.get("item_id") == iid
				and int(f.get("equip_slot", "0")) == ItemData.EquipSlot.AMULET
				and int(f.get("type", "0")) == ItemData.Type.ARMOR
				and int(f.get("tier", "0")) == tier
				and int(f.get("required_level", "0")) == _AMULET_LEVEL[tier], f)
			var others: Array = []
			for other in ["bonus_max_hp", "bonus_max_mana", "bonus_damage_percent", "armor_value", "damage"]:
				if other != field and f.has(other):
					others.append(other)
			check("  carries %s and nothing else" % field, amount > 0 and others.is_empty(), [amount, others])
			var icon: String = str(f.get("_icon_path", ""))
			var number := int(icon.get_file().get_basename().trim_prefix("a"))
			check("  wears a %s-coloured pack icon nobody else wears" % family,
				icon.begins_with("res://art/pack/amulets/a")
				and number >= int(icon_range[0]) and number <= int(icon_range[1])
				and not icons_seen.has(icon), [icon, icons_seen.get(icon, "")])
			icons_seen[icon] = iid
			var row: Dictionary = exported.get(iid, {})
			check("  and gamedata.json says the same (re-run the exporter if not)",
				not row.is_empty() and int(row.get(field, -1)) == amount
				and int(row.get("tier", -1)) == tier
				and int(row.get("required_level", -1)) == _AMULET_LEVEL[tier], row)
		var climbing := true
		for i in range(1, amounts.size()):
			if int(amounts[i]) <= int(amounts[i - 1]):
				climbing = false
		check("the %s bonus climbs with tier" % family, climbing, amounts)
	check("all fifteen are authored", authored.size() == 15, authored)

	var missing_fields: Array = []
	for iid in exported:
		for field in ["bonus_max_hp", "bonus_max_mana", "bonus_damage_percent"]:
			if not (exported[iid] as Dictionary).has(field):
				missing_fields.append("%s.%s" % [iid, field])
	check("every exported item carries the three bonus fields, so the server can sum them",
		missing_fields.is_empty(), missing_fields.slice(0, 5))
	var exporter := FileAccess.get_file_as_string("res://src/tools/exportgamedata.gd")
	for field in ["bonus_max_hp", "bonus_max_mana", "bonus_damage_percent"]:
		check("the exporter writes %s" % field, exporter.contains("\"%s\": item.%s" % [field, field]))

	var loaded := 0
	for iid in authored:
		var real: ItemData = ItemRegistry.get_item(iid)
		if real != null and real.icon != null:
			loaded += 1
	check_needs_pack("every amulet loads in game with its icon", loaded == authored.size(),
		"%d of %d" % [loaded, authored.size()])

	# ---- the character, with amulets the suite can build without the art ----
	var vit := _amulet_test_item("amulettest_vitality", "bonus_max_hp", 50)
	var arc := _amulet_test_item("amulettest_arcana", "bonus_max_mana", 40)
	var fury := _amulet_test_item("amulettest_fury", "bonus_damage_percent", 10)
	for d in [vit, arc, fury]:
		ItemRegistry._items[d.item_id] = d

	# THE BODY WITHOUT THE WORLD. Adding a warrior to the tree runs all of
	# player.gd's _ready() - camera, pets, the save - for checks about sums.
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.equipped = {}
	body.level = 10
	var bare_hp: int = body.max_hp
	var bare_mana: int = body.max_mana
	check("with nothing worn, max_hp is the class curve",
		bare_hp == PlayerStats.max_for(body.hp_base, body.hp_per_lvl, 10), bare_hp)

	body.hp = bare_hp
	check("a Vitality amulet can be put on", body.equip(vit.item_id))
	check("  it raises max_hp by its bonus", body.max_hp == bare_hp + 50, [body.max_hp, bare_hp])
	check("  but not hp - the ceiling moves, not the health", body.hp == bare_hp, body.hp)
	body.hp = body.max_hp
	body.unequip("amulet")
	check("taking it off brings max_hp back to the curve", body.max_hp == bare_hp, body.max_hp)
	check("  and hp comes down with it rather than sitting over the ceiling", body.hp == bare_hp, body.hp)
	body.hp = 40
	body.equip(vit.item_id)
	body.unequip("amulet")
	check("a wounded character stays exactly as wounded through on and off", body.hp == 40, body.hp)

	body.mana = bare_mana
	body.equip(arc.item_id)
	check("an Arcana amulet raises max_mana and nothing else",
		body.max_mana == bare_mana + 40 and body.max_hp == bare_hp, [body.max_mana, body.max_hp])
	body.mana = body.max_mana
	body.equip(fury.item_id)
	check("swapping it for Fury takes the mana back off",
		body.max_mana == bare_mana and body.mana == bare_mana, [body.max_mana, body.mana])

	var skill_mult: float = PlayerStats.damage_multiplier(body.attack, body.magic)
	check("a Fury amulet multiplies every hit by its percent",
		is_equal_approx(body.get_damage_multiplier(), skill_mult * 1.10),
		[body.get_damage_multiplier(), skill_mult])
	var with_fury: Vector2i = body.attack_damage_range()
	body.unequip("amulet")
	var without: Vector2i = body.attack_damage_range()
	check("  and the equipment panel's damage band shows it",
		with_fury.y > without.y and with_fury.x >= without.x, [with_fury, without])
	check("a negative damage percent is floored - a hit can never heal",
		is_equal_approx(PlayerStats.gear_damage_factor(-50), 1.0))
	body.equipped = {"amulet": "amulettest_nosuchthing"}
	check("an id the registry does not know adds nothing",
		body.equipped_bonus("bonus_max_hp") == 0 and body.equipped_bonus("bonus_damage_percent") == 0)

	# THE RECOMPUTE ITSELF MUST NOT CLAMP. It runs through the level setter in
	# the middle of CharacterData.load_character_state(), before hp is read, so
	# a clamp there would cut a loading character's health to a stale ceiling.
	body.equipped = {}
	body.hp = 99999
	body._recompute_max_stats()
	check("_recompute_max_stats() never touches hp (it runs mid-load)", body.hp == 99999, body.hp)

	# THE SERVER'S ANSWER, RENDERED. /api/character/unequip has already clamped
	# its own copy; the client has to land in the same place.
	body.equipped = {"amulet": vit.item_id}
	body._recompute_max_stats()
	body.hp = body.max_hp
	CharacterData._apply_equip_result(body, {"equipment": {}})
	check("the equip endpoint's answer moves the maxima and the pool with it",
		body.max_hp == bare_hp and body.hp == bare_hp, [body.max_hp, body.hp])
	body.free()

	# ---- the tooltip says what it does --------------------------------------
	var tip := ItemTooltip.new()
	check("a Vitality tooltip says +50 max health",
		tip._requirement_lines(vit).to_lower().contains("+50 max health"), tip._requirement_lines(vit))
	check("an Arcana tooltip says +40 max mana",
		tip._requirement_lines(arc).to_lower().contains("+40 max mana"), tip._requirement_lines(arc))
	check("a Fury tooltip says +10% damage",
		tip._requirement_lines(fury).to_lower().contains("+10% damage"), tip._requirement_lines(fury))
	tip.free()

	for d in [vit, arc, fury]:
		ItemRegistry._items.erase(d.item_id)


# =============================================================================
# THE PACE: element bands, the eight-hour curve, dangerous slimes, the finale
# =============================================================================
# The plan in the Economy and Progression doc, held against the data. Every
# number below is read from the .tres files, so retuning one enemy is caught
# here as a band drifting, not discovered as "the game got fast again".

const _BAND_OF := {"light": 1, "wind": 1, "water": 2, "ice": 2, "earth": 3, "fire": 4, "dark": 5}
const _BAND_HP := {1: 270, 2: 400, 3: 600, 4: 925, 5: 1400}
const _BAND_HIT := {1: 14, 2: 20, 3: 28, 4: 40, 5: 55}
# The non-slime normals of each element - what a band's average is taken over.
# The plain bush mage is earth and the plain fire sprite is fire.
const _BAND_FAMILY := {
	"light": ["lightsprite", "lightfiresprite", "lightbushmage", "lightbushsniper"],
	"wind": ["windsprite", "windfiresprite", "windbushmage", "windbushsniper"],
	"water": ["watersprite", "waterfiresprite", "waterbushmage", "waterbushsniper"],
	"ice": ["icesprite", "icefiresprite", "icebushmage", "icebushsniper"],
	"earth": ["earthsprite", "earthfiresprite", "earthbushsniper", "bushmage"],
	"fire": ["firebushmage", "firesprite"],
	"dark": ["darksprite", "darkfiresprite", "darkbushmage", "darkbushsniper"],
}
const _SLIME_ELEMENTS := ["light", "wind", "water", "ice", "earth", "dark"]
const _LADDER := ["light", "wind", "water", "ice", "earth", "fire", "dark"]


func _enemy_fields(enemy_id: String) -> Dictionary:
	return _tres_fields("res://data/enemies/%s.tres" % enemy_id)


func _near(value: float, target: float, tolerance: float) -> bool:
	return absf(value - target) <= absf(target) * tolerance


func _test_the_game_has_a_pace() -> void:
	section("PACE — element bands, the eight-hour curve, dangerous slimes, the Crowned's door")

	# ---- the curve ----------------------------------------------------------
	check("level 1 costs the curve's 1,250 XP", GameConstants.xp_needed_for_level(1) == 1250,
		GameConstants.xp_needed_for_level(1))
	check("a brand-new save starts on the same first level",
		int(CharacterData.SAVEABLE_STATS["xp_next"]) == GameConstants.xp_needed_for_level(1),
		CharacterData.SAVEABLE_STATS["xp_next"])
	var fresh: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	check("so does a freshly built player",
		int(fresh.get("xp_next")) == GameConstants.xp_needed_for_level(1), fresh.get("xp_next"))
	fresh.free()

	# ---- the bands ----------------------------------------------------------
	var element_hp: Dictionary = {}
	var element_hit: Dictionary = {}
	var band_xp: Dictionary = {}
	var off_band: Array = []
	var odd_ratio: Array = []
	for el in _LADDER:
		var band: int = _BAND_OF[el]
		var hps: Array = []
		var hits: Array = []
		for eid in _BAND_FAMILY[el]:
			var f := _enemy_fields(eid)
			var hp := int(f.get("max_hp", "0"))
			var xp := int(f.get("xp_reward", "0"))
			hps.append(hp)
			hits.append(int(f.get("projectile_damage", "0")))
			if not band_xp.has(band):
				band_xp[band] = []
			band_xp[band].append(xp)
			if int(f.get("max_loot_tier", "0")) != band:
				off_band.append("%s tier %s" % [eid, f.get("max_loot_tier")])
			# XP stays at today's ratio to health, about 0.37 a point.
			if hp <= 0 or float(xp) / hp < 0.30 or float(xp) / hp > 0.42:
				odd_ratio.append("%s %d/%d" % [eid, xp, hp])
		element_hp[el] = hps.reduce(func(a, b): return a + b, 0) / float(hps.size())
		element_hit[el] = hits.reduce(func(a, b): return a + b, 0) / float(hits.size())
	check("every normal drops up to its band's tier (light/wind iron ... dark ember)",
		off_band.is_empty(), off_band)
	check("every normal pays about 0.37 XP per point of health", odd_ratio.is_empty(), odd_ratio)
	for band in [1, 2, 3, 4, 5]:
		var hp_sum := 0.0
		var hit_sum := 0.0
		var n := 0
		for el in _LADDER:
			if _BAND_OF[el] == band:
				hp_sum += element_hp[el]
				hit_sum += element_hit[el]
				n += 1
		check("band %d: normal health averages about %d" % [band, _BAND_HP[band]],
			_near(hp_sum / n, _BAND_HP[band], 0.03), snappedf(hp_sum / n, 0.1))
		check("band %d: a normal hit averages about %d" % [band, _BAND_HIT[band]],
			_near(hit_sum / n, _BAND_HIT[band], 0.06), snappedf(hit_sum / n, 0.1))
	var climbing := true
	for i in range(1, _LADDER.size()):
		if element_hp[_LADDER[i]] <= element_hp[_LADDER[i - 1]]:
			climbing = false
	check("health climbs light, wind, water, ice, earth, fire, dark", climbing, element_hp)

	# ---- the eight hours ----------------------------------------------------
	# Five kills a minute in the band that matches your level. The plan's
	# checkpoints are level 5 in a quarter hour, 10 in about one, 16 in about
	# three and 22 in about eight.
	var avg_xp: Dictionary = {}
	for band in band_xp:
		avg_xp[band] = (band_xp[band] as Array).reduce(func(a, b): return a + b, 0) / float((band_xp[band] as Array).size())
	var minutes := 0.0
	var at: Dictionary = {}
	for level in range(1, 22):
		var band: int = 1 if level < 5 else 2 if level < 10 else 3 if level < 16 else 4
		minutes += GameConstants.xp_needed_for_level(level) / avg_xp[band] / 5.0
		at[level + 1] = minutes / 60.0
	check("level 5 in about a quarter of an hour", at[5] > 0.18 and at[5] < 0.35, snappedf(at[5], 0.01))
	check("level 10 in about an hour", at[10] > 0.7 and at[10] < 1.3, snappedf(at[10], 0.01))
	check("level 16 in about three hours", at[16] > 2.3 and at[16] < 3.5, snappedf(at[16], 0.01))
	check("level 22 in about eight hours", at[22] > 7.0 and at[22] < 9.0, snappedf(at[22], 0.01))

	# ---- the slimes, as data ------------------------------------------------
	var field_text := FileAccess.get_file_as_string("res://scene/field.tscn")
	for el in _SLIME_ELEMENTS:
		var large := _enemy_fields(el + "slimelarge")
		var small := _enemy_fields(el + "slime")
		var large_text := FileAccess.get_file_as_string("res://data/enemies/%sslimelarge.tres" % el)
		check("%s: the large splits into the %s small, same element, and pays nothing itself" % [el, el],
			large_text.contains('path="res://data/enemies/%sslime.tres"' % el)
			and large_text.contains("split_into = ExtResource(")
			and large.get("element") == small.get("element")
			and large.get("grants_rewards") == "false", [large, small])
		check("  large health about twice the band's normal, each small a third",
			_near(int(large.get("max_hp", "0")), 2.0 * element_hp[el], 0.02)
			and _near(int(small.get("max_hp", "0")), element_hp[el] / 3.0, 0.03),
			[large.get("max_hp"), small.get("max_hp"), element_hp[el]])
		check("  and a small's arrow hits for about three quarters of a normal hit",
			absf(int(small.get("projectile_damage", "0")) - 0.75 * element_hit[el]) <= 1.0,
			[small.get("projectile_damage"), element_hit[el]])
		check("  the field places the large, not the small",
			field_text.contains('path="res://scene/enemy/%sslimelarge.tscn"' % el)
			and not field_text.contains('path="res://scene/enemy/%sslime.tscn"' % el))

	# ---- the slimes, alive --------------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var large_node: Node = (load("res://scene/enemy/windslimelarge.tscn") as PackedScene).instantiate()
	holder.add_child(large_node)
	await get_tree().process_frame
	check("a placed wind slime is the large, on the large's data",
		not large_node.is_small and large_node.enemy_data != null
		and large_node.enemy_data.enemy_id == "windslimelarge")
	var heard: Array = [false]
	large_node.died.connect(func(): heard[0] = true)
	var smalls_expected: int = int(large_node.small_count)
	var wait_for: float = float(large_node.hitflash_duration) + 0.3
	large_node._begin_split()
	check("splitting tells the respawner the placed large is gone (died, before the await)", heard[0])
	await get_tree().create_timer(wait_for).timeout
	await get_tree().process_frame
	var smalls: Array = []
	for c in holder.get_children():
		if c is PoisonSlime and is_instance_valid(c) and c.is_small:
			smalls.append(c)
	var wrong: Array = []
	for s in smalls:
		if s.enemy_data == null or s.enemy_data.enemy_id != "windslime" or s.current_element() != Element.Type.WIND:
			wrong.append(s.enemy_data.enemy_id if s.enemy_data != null else "null")
	check("it bursts into %d wind smalls on the windslime profile" % smalls_expected,
		smalls.size() == smalls_expected and wrong.is_empty(), [smalls.size(), wrong])

	var twin_parent: Node = (load("res://scene/enemy/windslimelarge.tscn") as PackedScene).instantiate()
	holder.add_child(twin_parent)
	await get_tree().process_frame
	var before: Array = holder.get_children()
	twin_parent._spawn_slime(false, Vector2(40, 0))
	await get_tree().process_frame
	var twin: Node = null
	for c in holder.get_children():
		if not before.has(c):
			twin = c
	check("its twin is another large wind slime, with its duplication spent",
		twin != null and not twin.is_small and twin.enemy_data.enemy_id == "windslimelarge"
		and twin._has_duplicated)

	var poison: Node = (load("res://scene/enemy/poisonslime.tscn") as PackedScene).instantiate()
	holder.add_child(poison)
	await get_tree().process_frame
	before = holder.get_children()
	poison._spawn_slime(true, Vector2(-40, 0))
	await get_tree().process_frame
	var poison_small: Node = null
	for c in holder.get_children():
		if not before.has(c):
			poison_small = c
	check("the original poison slime still bursts into poisonslimesmall",
		poison_small != null and poison_small.enemy_data != null
		and poison_small.enemy_data.enemy_id == "poisonslimesmall")

	# ---- a bush mage hits for its own profile -------------------------------
	var mage: Node = (load("res://scene/enemy/darkbushmage.tscn") as PackedScene).instantiate()
	holder.add_child(mage)
	await get_tree().process_frame
	var scene_root: Node = get_tree().current_scene
	var groundeffects: Node = get_tree().get_first_node_in_group("groundeffects")
	var vine_parent: Node = groundeffects if groundeffects != null else scene_root
	var had: Array = vine_parent.get_children()
	mage._spawn_vine()
	var vine: Node = null
	for c in vine_parent.get_children():
		if not had.has(c):
			vine = c
	check("a dark bush mage's vine hits for its .tres projectile_damage, not the script's 8",
		vine != null and int(vine.damage) == int(_enemy_fields("darkbushmage").get("projectile_damage", "0")),
		vine.damage if vine != null else "no vine")
	if vine != null:
		vine.queue_free()
	holder.queue_free()

	# ---- the finale ---------------------------------------------------------
	var arena := FileAccess.get_file_as_string("res://scene/bossarena.tscn")
	var room := FileAccess.get_file_as_string("res://scene/boss.tscn")
	check("the arena's victory door leads to the Crowned's room",
		arena.contains('destination_scene_path = "res://scene/boss.tscn"')
		and arena.contains('target_spawn_id = "boss_entrance"'))
	check("and that room has the marker it lands on, and a registered area",
		room.contains('portal_id = "boss_entrance"') and AreaRegistry.has_area("boss"))
	var crowned := _enemy_fields("boss")
	var fire := _enemy_fields("fireboss")
	check("the fire boss is about 9,200 health", int(fire.get("max_hp", "0")) == 9200, fire.get("max_hp"))
	check("the Crowned is the hardest fight in the game and drops the best tier",
		int(crowned.get("max_hp", "0")) > int(fire.get("max_hp", "0"))
		and int(crowned.get("max_loot_tier", "0")) == 6
		and int(crowned.get("xp_reward", "0")) > int(fire.get("xp_reward", "0")), crowned)


# =============================================================================
# BETTER LOOT CARRIES MORE, AND LEGENDARY IS RARE
# =============================================================================
# Every piece from jade up adds something beyond its armour or damage, and the
# something grows with the tier: plate adds health, cloth adds mana, weapons
# add damage, and the plain rings and amulets add a little of all three. Iron
# is Common and plain. Ember - Legendary - carries the most, and drops rarely:
# about one an hour in the dark band, 1 in 4 from the fire boss and the
# Crowned, never from the other five bosses.

const _PLATE := ["helm", "chest", "legs", "boots", "shield"]
const _CLOTH := ["hood", "robe", "trousers", "slippers"]
const _WEAPONS := ["sword", "maul", "staff", "scepter"]
const _MATERIALS := ["iron", "jade", "cobalt", "amethyst", "ember"]
const _BONUS_FIELDS := ["bonus_max_hp", "bonus_max_mana", "bonus_damage_percent"]


func _item_fields(folder: String, item_id: String) -> Dictionary:
	return _tres_fields("res://data/items/%s/%s.tres" % [folder, item_id])


func _odds_of(enemy_id: String) -> Array:
	var raw: String = str(_enemy_fields(enemy_id).get("tier_odds", ""))
	var inner: String = raw.trim_prefix("PackedFloat32Array(").trim_suffix(")")
	var out: Array = []
	for part in inner.split(",", false):
		out.append(float(part.strip_edges()))
	return out


func _test_better_loot_carries_more() -> void:
	section("LOOT — every tier from jade up carries a bonus, and legendary is rare")

	# ---- the gear ladder ----------------------------------------------------
	var exported: Dictionary = {}
	for row in _load_gamedata().get("items", []):
		if row is Dictionary:
			exported[str(row.get("item_id", ""))] = row
	var groups := {"bonus_max_hp": _PLATE, "bonus_max_mana": _CLOTH, "bonus_damage_percent": _WEAPONS}
	var set_totals: Dictionary = {}
	for field in groups:
		var folder: String = "weapons" if field == "bonus_damage_percent" else "armour"
		for piece in groups[field]:
			var last := 0
			var climbing := true
			var wrong: Array = []
			for mat in _MATERIALS:
				var iid: String = mat + piece
				var f := _item_fields(folder, iid)
				var amount := int(f.get(field, "0"))
				for other in _BONUS_FIELDS:
					if other != field and f.has(other):
						wrong.append("%s has %s" % [iid, other])
				if mat == "iron":
					if amount != 0:
						wrong.append("iron %s has %d - Common stays plain" % [piece, amount])
					continue
				if amount <= last:
					climbing = false
				last = amount
				set_totals["%s:%s" % [field, mat]] = int(set_totals.get("%s:%s" % [field, mat], 0)) + amount
				var row: Dictionary = exported.get(iid, {})
				if int(row.get(field, -1)) != amount:
					wrong.append("gamedata.json says %s for %s (re-export)" % [row.get(field), iid])
			check("%s: %s from jade up, climbing to ember, and nothing else" % [piece, field.trim_prefix("bonus_")],
				climbing and wrong.is_empty(), wrong)
	check("a full ember plate set is +100 health (jade +20, cobalt +40, amethyst +65)",
		set_totals.get("bonus_max_hp:ember") == 100 and set_totals.get("bonus_max_hp:jade") == 20
		and set_totals.get("bonus_max_hp:cobalt") == 40 and set_totals.get("bonus_max_hp:amethyst") == 65,
		set_totals)
	check("a full ember cloth set is +120 mana (jade +24, cobalt +48, amethyst +78)",
		set_totals.get("bonus_max_mana:ember") == 120 and set_totals.get("bonus_max_mana:jade") == 24
		and set_totals.get("bonus_max_mana:cobalt") == 48 and set_totals.get("bonus_max_mana:amethyst") == 78,
		set_totals)

	# ---- the plain jewellery ------------------------------------------------
	var specialist := {2: "lesser", 3: "", 4: "greater", 5: "exalted"}
	var tier_of := {"iron": 1, "jade": 2, "cobalt": 3, "amethyst": 4, "ember": 5}
	for kind in ["amulet", "ring"]:
		var prev := [-1, -1, -1, -1]
		var climbing := true
		var wrong: Array = []
		for mat in _MATERIALS:
			var f := _item_fields("armour", mat + kind)
			var now := [int(f.get("bonus_max_hp", "0")), int(f.get("bonus_max_mana", "0")),
				int(f.get("bonus_damage_percent", "0")), int(f.get("armor_value", "0"))]
			for i in range(4):
				if now[i] <= 0:
					wrong.append("%s%s has no %s" % [mat, kind, ["health", "mana", "damage", "armour"][i]])
				if now[i] < prev[i]:
					climbing = false
			prev = now
			var row: Dictionary = exported.get(mat + kind, {})
			for field in _BONUS_FIELDS:
				if int(row.get(field, -1)) != int(f.get(field, "0")):
					wrong.append("gamedata.json disagrees on %s%s.%s" % [mat, kind, field])
		check("every plain %s, iron to ember, adds health, mana, damage and armour, never shrinking" % kind,
			climbing and wrong.is_empty(), wrong)

	for mat in _MATERIALS:
		var amulet := _item_fields("armour", mat + "amulet")
		var ring := _item_fields("armour", mat + "ring")
		check("the %s ring gives no more than the %s amulet" % [mat, mat],
			int(ring.get("bonus_max_hp", "0")) <= int(amulet.get("bonus_max_hp", "0"))
			and int(ring.get("bonus_max_mana", "0")) <= int(amulet.get("bonus_max_mana", "0"))
			and int(ring.get("bonus_damage_percent", "0")) <= int(amulet.get("bonus_damage_percent", "0")))

	# THE SPECIALISTS STAY SPECIAL. The plain amulet is the all-rounder; at its
	# own tier each family must still win its own stat, or it is the one that
	# becomes vendor loot.
	var losers: Array = []
	for mat in ["jade", "cobalt", "amethyst", "ember"]:
		var tier: int = tier_of[mat]
		var plain := _item_fields("armour", mat + "amulet")
		for pair in [["vitality", "bonus_max_hp"], ["arcana", "bonus_max_mana"],
				["fury", "bonus_damage_percent"], ["ward", "armor_value"]]:
			var sid: String = "%s%samulet" % [specialist[tier], pair[0]]
			var s := _item_fields("amulets", sid)
			if s.is_empty():
				continue   # Vitality starts at tier 3
			if int(s.get(pair[1], "0")) <= int(plain.get(pair[1], "0")):
				losers.append("%s %s vs %s %s" % [sid, s.get(pair[1]), mat + "amulet", plain.get(pair[1])])
	check("each bonus family beats the plain amulet of its tier at its own stat", losers.is_empty(), losers)

	# ---- worn, with the real items (needs the art pack to load them) --------
	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.equipped = {}
	body.level = 22
	var bare: int = body.max_hp
	body.equipped = {"chest": "emberchest", "legs": "emberlegs", "helm": "emberhelm",
		"boots": "emberboots", "shield": "embershield", "ring": "emberring",
		"amulet": "emberamulet", "weapon": "embersword"}
	body._recompute_max_stats()
	check_needs_pack("a level 22 warrior in full ember is +150 health (100 plate, 20 ring, 30 amulet)",
		body.max_hp == bare + 150, [body.max_hp, bare])
	check_needs_pack("and hits 15% harder (8 sword, 3 ring, 4 amulet)",
		body.equipped_bonus("bonus_damage_percent") == 15, body.equipped_bonus("bonus_damage_percent"))
	body.free()

	# ---- legendary is rare --------------------------------------------------
	for eid in ["darksprite", "darkfiresprite", "darkbushmage", "darkbushsniper", "darkslime"]:
		var odds := _odds_of(eid)
		check("%s: ember on 3%% of its item slots, not 15%%" % eid,
			int(_enemy_fields(eid).get("max_loot_tier", "0")) == 5 and odds.size() == 3
			and is_equal_approx(odds[0], 0.03), odds)
	for eid in ["fireboss", "boss"]:
		var odds := _odds_of(eid)
		check("%s: legendary 1 in 4, amethyst otherwise (tier 6 has no gear)" % eid,
			odds.size() == 3 and is_equal_approx(odds[0], 0.0) and is_equal_approx(odds[1], 0.25)
			and is_equal_approx(odds[2], 0.75), odds)
	for eid in ["lightboss", "windboss", "waterboss", "iceboss", "earthboss"]:
		var top: int = int(_enemy_fields(eid).get("max_loot_tier", "0"))
		var odds := _odds_of(eid)
		var ember_share := 0.0
		for i in range(odds.size()):
			if top - i >= 5:
				ember_share += odds[i]
		var amethyst_share: float = odds[top - 4] if top - 4 < odds.size() else 0.0
		check("%s: never legendary, amethyst about a third of the time" % eid,
			is_zero_approx(ember_share) and is_equal_approx(amethyst_share, 0.35), [top, odds])


# =============================================================================
# BOSSES HIT FOR THEIR BAND
# =============================================================================
# All seven bosses run bossenemy.gd, and all seven hit for its 34 / 45 / 22
# whatever their .tres said: the six elemental ones had a projectile_damage
# nothing read, and the Crowned had none. So when the normals moved into bands
# the Crowned's spike (37 after dark's profile) was softer than a dark bush
# mage's 55, and the light boss hit nearly three times its band. The spike is
# the .tres's projectile_damage now, 1.5x its band's normal hit; the swing and
# the stalker's trail keep the 45 : 34 and 22 : 34 they were tuned at.

const _BOSS_BAND := {"lightboss": 1, "windboss": 1, "waterboss": 2, "iceboss": 2,
	"earthboss": 3, "fireboss": 4, "boss": 5}


func _boss_scene_path(enemy_id: String) -> String:
	# The Crowned is the bare scene; it takes boss.tres in _ready().
	return "res://scene/enemy/bossenemy.tscn" if enemy_id == "boss" \
		else "res://scene/enemy/%s.tscn" % enemy_id


func _test_bosses_hit_for_their_band() -> void:
	section("BOSSES HIT FOR THEIR BAND — spike, swing and trail from the boss's own data")

	var profile: Dictionary = (load("res://src/projectiles/bossprojectile.gd") as Script) \
		.get_script_constant_map().get("ELEMENT_PROFILE", {})
	var boss_src := FileAccess.get_file_as_string("res://src/enemies/bossenemy.gd")

	# ---- the data -----------------------------------------------------------
	var last_spike := 0
	var climbs := true
	for eid in _BOSS_BAND:
		var band: int = _BOSS_BAND[eid]
		var spike := int(_enemy_fields(eid).get("projectile_damage", "0"))
		check("%s: its spike is 1.5x a band-%d normal hit (%d)" % [eid, band, roundi(1.5 * _BAND_HIT[band])],
			spike == roundi(1.5 * _BAND_HIT[band]), spike)
		if spike < last_spike:
			climbs = false
		last_spike = spike
	check("and the spikes climb band by band, the Crowned's the biggest", climbs)

	# ---- the bosses themselves ----------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var target := Node2D.new()
	holder.add_child(target)
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	if container == null:
		container = get_tree().current_scene
	var hits: Dictionary = {}
	for eid in _BOSS_BAND:
		var band: int = _BOSS_BAND[eid]
		var spike := int(_enemy_fields(eid).get("projectile_damage", "0"))
		var boss: Node = (load(_boss_scene_path(eid)) as PackedScene).instantiate()
		check("%s: spike %d, swing %d, trail %d - the shares the fight was tuned at" % [
				eid, spike, roundi(spike * 45.0 / 34.0), roundi(spike * 22.0 / 34.0)],
			boss.spike_damage() == spike
			and boss.melee_damage() == roundi(spike * 45.0 / 34.0)
			and boss.trail_damage() == roundi(spike * 22.0 / 34.0),
			[boss.spike_damage(), boss.melee_damage(), boss.trail_damage()])
		if boss.enemy_data == null:
			# What _ready() would do; the bare scene answered as the Crowned above.
			boss.enemy_data = boss.ENEMY_DATA

		# A real spike, through the one function both tracks go through.
		var p: Dictionary = profile.get(boss.current_element(), profile.get(Element.Type.NONE, {}))
		var scaled := maxi(1, int(round(spike * float(p.get("damage", 1.0)))))
		var had: Array = holder.get_children()
		boss._spawn_one_eruption(holder, Vector2.ZERO, 1.0, boss.SPIKE_BASE_RADIUS, boss.eruption_scene)
		var eruption: Node = null
		for c in holder.get_children():
			if not had.has(c):
				eruption = c
		check("  a real spike lands for %d (its element's x%s on top)" % [scaled, p.get("damage", 1.0)],
			eruption != null and int(eruption.damage) == scaled,
			eruption.damage if eruption != null else "no spike")
		check("  which is more than a band-%d normal hit and at most twice one" % band,
			eruption != null and int(eruption.damage) > int(_BAND_HIT[band])
			and int(eruption.damage) <= 2 * int(_BAND_HIT[band]),
			[eruption.damage if eruption != null else -1, _BAND_HIT[band]])
		hits[eid] = int(eruption.damage) if eruption != null else 0
		if eruption != null:
			eruption.free()

		# A real stalker, handed what _spawn_stalker() hands it, dropping a pillar.
		var stalker: Node2D = Node2D.new()
		stalker.set_script(boss.STALKER_SCRIPT)
		holder.add_child(stalker)
		stalker.setup(target, Projectiles.variant_of(boss.eruption_scene, boss.current_element()),
			boss.trail_damage(), boss.current_element())
		var before: Array = container.get_children()
		stalker._drop_pillar()
		var pillar: Node = null
		for c in container.get_children():
			if not before.has(c):
				pillar = c
		# The trail wears the BOSS's element, stamped by the stalker - there is
		# no dark pillar scene, so without the stamp the Crowned's trail was
		# plain (54, a full-strength ring) while its spikes were dark.
		var trail_scaled := maxi(1, int(round(boss.trail_damage() * float(p.get("damage", 1.0)))))
		check("  its stalker's trail drops %s pillars for %d" % [Element.name_for(boss.current_element()), trail_scaled],
			pillar != null and int(pillar.damage) == trail_scaled
			and int(pillar.element) == boss.current_element(),
			[pillar.damage, pillar.element] if pillar != null else "no pillar")
		if pillar != null:
			pillar.free()
		stalker.free()
		boss.free()
	holder.queue_free()
	check("the Crowned hits hardest of the seven",
		hits["boss"] == hits.values().max(), hits)

	# ---- the wiring the bosses above cannot show outside a fight -------------
	var swing_at := _first_code_index(boss_src, "func _land_swing(", 0)
	var swing_end := _first_code_index(boss_src, "\nfunc ", swing_at + 1)
	check("the swing lands for melee_damage(), not the bare melee_power",
		_within(_first_code_index(boss_src, "take_damage(melee_damage()", swing_at), swing_end) != -1
		and _within(_first_code_index(boss_src, "take_damage(melee_power", swing_at), swing_end) == -1)
	var stalk_at := _first_code_index(boss_src, "func _spawn_stalker(", 0)
	var stalk_end := _first_code_index(boss_src, "\nfunc ", stalk_at + 1)
	check("and _spawn_stalker() hands the stalker trail_damage() and the boss's element",
		_within(_first_code_index(boss_src, "trail_damage(),\n\t\tcurrent_element())", stalk_at), stalk_end) != -1)
	print("  bosses: spikes %s" % str(hits))


# =============================================================================
# GEAR BONUSES ARE SHOWN: THE DOLL'S TOTALS AND THE TOOLTIP'S COMPARISON
# =============================================================================
# Every tier from jade up adds health, mana or damage, and until this the only
# place to read one was a single tooltip - with nothing saying whether it beat
# what you were wearing. The Gear window sums them (from the same
# equipped_bonus() the character uses), and a tooltip over a piece of gear
# lists what would change, green or red, against the piece in that slot.

func _gear_test_item(item_id: String, slot: int, fields: Dictionary) -> ItemData:
	var d := ItemData.new()
	d.item_id = item_id
	d.display_name = item_id.capitalize()
	d.equip_slot = slot
	for f in fields:
		d.set(f, fields[f])
	return d


func _test_gear_bonuses_are_shown() -> void:
	section("GEAR BONUSES ARE SHOWN — the Gear window's totals, the tooltip's comparison")

	var chest := _gear_test_item("geartest_chest", ItemData.EquipSlot.CHEST,
		{"armor_value": 10, "bonus_max_hp": 40})
	var better := _gear_test_item("geartest_chest_b", ItemData.EquipSlot.CHEST,
		{"armor_value": 16, "bonus_max_hp": 30})
	var twin := _gear_test_item("geartest_chest_c", ItemData.EquipSlot.CHEST,
		{"armor_value": 10, "bonus_max_hp": 40})
	var ring := _gear_test_item("geartest_ring", ItemData.EquipSlot.RING,
		{"bonus_max_mana": 12, "bonus_damage_percent": 2})
	var boots := _gear_test_item("geartest_boots", ItemData.EquipSlot.BOOTS, {"armor_value": 4})
	var robe := _gear_test_item("geartest_robe", ItemData.EquipSlot.CHEST,
		{"armor_value": 3, "bonus_max_mana": 48})
	robe.required_classes.append("geartest_nobody")
	var stone := _gear_test_item("geartest_stone", ItemData.EquipSlot.NONE, {})
	for d in [chest, better, twin, ring, boots, robe, stone]:
		ItemRegistry._items[d.item_id] = d

	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	body.level = 10
	body.equipped = {}

	# ---- the Gear window ----------------------------------------------------
	var panel: Node = (load("res://scene/ui/equipment/equipmentpanel.tscn") as PackedScene).instantiate()
	add_child(panel)
	await get_tree().process_frame
	panel.player = body
	panel._refresh_summary()
	check("wearing nothing, the three bonus rows read as a dash, not +0",
		panel.health_bonus_label.text == "-" and panel.mana_bonus_label.text == "-"
		and panel.damage_bonus_label.text == "-",
		[panel.health_bonus_label.text, panel.mana_bonus_label.text, panel.damage_bonus_label.text])
	body.equipped = {"chest": chest.item_id, "ring": ring.item_id}
	panel._refresh_summary()
	check("in a +40 health chest and a +12 mana, +2% ring: +40, +12, +2%",
		panel.health_bonus_label.text == "+40" and panel.mana_bonus_label.text == "+12"
		and panel.damage_bonus_label.text == "+2%",
		[panel.health_bonus_label.text, panel.mana_bonus_label.text, panel.damage_bonus_label.text])
	check("  in the good colour",
		panel.health_bonus_label.get_theme_color("font_color") == panel.COLOUR_GOOD)
	check("  and they are the character's own sums, the ones its maxima use",
		body.equipped_bonus("bonus_max_hp") == 40 and body.equipped_bonus("bonus_max_mana") == 12)
	panel.queue_free()

	# ---- compare_rows, the arithmetic ---------------------------------------
	var Tip: Script = load("res://src/ui/inventory/itemtooltip.gd")
	var rows: Array = Tip.compare_rows(better, chest)
	check("a chest with 6 more armour and 10 less health: two rows, in that order",
		rows.size() == 2 and rows[0]["label"] == "Armour" and int(rows[0]["delta"]) == 6
		and rows[1]["label"] == "Max health" and int(rows[1]["delta"]) == -10, rows)
	check("against an empty slot everything is a gain",
		Tip.compare_rows(ring, null).size() == 2
		and int(Tip.compare_rows(ring, null)[1]["delta"]) == 2
		and Tip.compare_rows(ring, null)[1]["suffix"] == "%", Tip.compare_rows(ring, null))
	check("and a piece identical to the worn one changes nothing",
		Tip.compare_rows(twin, chest).is_empty())

	# ---- the tooltip ---------------------------------------------------------
	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(tip)
	await get_tree().process_frame
	check("a tooltip for a stone ends at its text: no rule, no empty band under it",
		_tip_comparing(tip, stone, null, body) == "hidden")
	check("a tooltip for gear compares it with what is worn in that slot",
		_tip_comparing(tip, better, null, body) == "shown"
		and tip.compare_heading.text == "Compared with your Geartest Chest:", tip.compare_heading.text)
	var got := _tip_rows(tip)
	check("  +6 armour in green, -10 max health in red",
		got.size() == 2 and got[0] == ["Armour", "+6", tip.COMPARE_BETTER]
		and got[1] == ["Max health", "-10", tip.COMPARE_WORSE], got)
	var bare := _tip_comparing(tip, boots, null, body)
	got = _tip_rows(tip)
	check("boots over bare feet: one line saying it is all a gain, not the stat line again as rows",
		bare == "shown" and tip.compare_heading.text.begins_with("Nothing is worn there yet")
		and got.is_empty(), [tip.compare_heading.text, got])
	_tip_comparing(tip, twin, null, body)
	got = _tip_rows(tip)
	check("the same stats as the worn piece say No change",
		got.size() == 1 and got[0][0] == "No change", got)
	var square: Node = (load("res://scene/ui/equipment/equipmentslot.tscn") as PackedScene).instantiate()
	check("the piece on the doll compares with nothing - it is what is worn",
		_tip_comparing(tip, chest, square, body) == "hidden")
	square.free()
	check("gear this class can never wear is not compared",
		_tip_comparing(tip, robe, null, body) == "hidden")
	check("nor is anything when nobody is playing",
		_tip_comparing(tip, better, null, null) == "hidden")
	tip.show_for_stack(ItemStack.new(better, 1), null)
	var show_src := FileAccess.get_file_as_string("res://src/ui/inventory/itemtooltip.gd")
	var show_at := _first_code_index(show_src, "func show_for_stack(", 0)
	var show_end := _first_code_index(show_src, "\nfunc ", show_at + 1)
	check("show_for_stack() asks for the comparison with the player who is playing",
		_within(_first_code_index(show_src, "populate_comparison(stack.data, source_slot, get_tree().get_first_node_in_group(\"player\"))", show_at), show_end) != -1)
	check("  and fits itself to what it holds, so a short tooltip is not a tall one",
		_within(_first_code_index(show_src, "reset_size()", show_at), show_end) != -1)
	tip.queue_free()

	body.free()
	for d in [chest, better, twin, ring, boots, robe, stone]:
		ItemRegistry._items.erase(d.item_id)
	print("  gear bonuses: the Gear window sums them, the tooltip compares them")


func _tip_comparing(tip: Node, data: ItemData, source: Node, wearer: Node) -> String:
	# "shown" or "hidden" when the rows and the rule above them agree, "mixed"
	# when they do not - a rule left up over no rows is the empty band this
	# replaced, and it has to fail both ways.
	tip.populate_comparison(data, source, wearer)
	if tip.stats_box.visible and tip.stats_rule.visible:
		return "shown"
	if not tip.stats_box.visible and not tip.stats_rule.visible:
		return "hidden"
	return "mixed"


func _tip_rows(tip: Node) -> Array:
	# [label, value, colour] for each comparison row, in order.
	var out: Array = []
	for row in tip.stats_box.get_children():
		if not row.has_meta("compare_row"):
			continue
		var value: Label = row.get_node("hboxcontainer/statvalue")
		out.append([row.get_node("hboxcontainer/statlabel").text, value.text,
			value.get_theme_color("font_color")])
	return out


# =============================================================================
# A TOOLTIP SAYS A THING ONCE
# =============================================================================
# Every potion and cooked fish ended its description with "Restores 260 HP."
# and the tooltip then printed the data's own line under it - so it said the
# number twice, the second time as "Restores 260 Hp" because capitalize() does
# that to "hp". The descriptions are flavour now; the data line is the number.

func _test_tooltips_say_it_once() -> void:
	section("A TOOLTIP SAYS A THING ONCE — the restore line comes from the data, not the description")

	var doubled: Array = []
	var restoring := 0
	for folder in ["consumables", "fishing"]:
		var dir := DirAccess.open("res://data/items/%s" % folder)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var fields := _tres_fields("res://data/items/%s/%s" % [folder, f])
			if int(fields.get("restore_amount", "0")) <= 0:
				continue
			restoring += 1
			if str(fields.get("description", "")).to_lower().contains("restores"):
				doubled.append(f.get_basename())
	check("no restoring item's description repeats the restore line (%d items)" % restoring,
		restoring >= 20 and doubled.is_empty(), doubled)

	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	add_child(tip)
	await get_tree().process_frame
	var potion := ItemData.new()
	potion.item_id = "saytest_potion"
	potion.restore_amount = 260
	potion.restore_target = ItemData.RestoreTarget.HP
	check("a health potion's line reads Restores 260 Health, not Hp",
		tip._requirement_lines(potion) == "Restores 260 Health", tip._requirement_lines(potion))
	potion.restore_target = ItemData.RestoreTarget.MANA
	check("and a mana potion's, Restores 260 Mana",
		tip._requirement_lines(potion) == "Restores 260 Mana", tip._requirement_lines(potion))
	tip.queue_free()
	print("  tooltips: the restore number is said once, from the data")


# =============================================================================
# THE SWEEP: FINISHED HALVES WITH NOTHING JOINED TO THEM
# =============================================================================
# One pass over the client for "a thing that exists and nothing reaches it",
# this project's most repeated bug. Each check below is one of those, joined.

func _code_src(path: String) -> String:
	return _code_only(FileAccess.get_file_as_string(path))


func _all_gd_under(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	_gd_files_under(dir_path, out)
	return out


func _all_files_under(dir_path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			out.append_array(_all_files_under(dir_path.path_join(sub), suffix))
	for file in dir.get_files():
		if file.ends_with(suffix):
			out.append(dir_path.path_join(file))
	return out


func _func_body(src: String, header: String) -> String:
	# The text of one function, from its header to the next top-level func.
	var at := _first_code_index(src, header, 0)
	if at == -1:
		return ""
	var end := _first_code_index(src, "\nfunc ", at + 1)
	return src.substr(at, (end if end != -1 else src.length()) - at)


func _test_the_sweep_wiring() -> void:
	section("THE SWEEP — attack from the server, failed pushes retried, and six small wires joined")

	# ---- attack XP is the server's, copied onto the bar ---------------------
	var callers: Array = []
	for path in _all_gd_under("res://src"):
		if path.ends_with("testrunner.gd") or path.ends_with("combat.gd") or path.ends_with("player.gd"):
			continue
		if _code_src(path).contains("gain_attack_xp("):
			callers.append(path.get_file())
	check("no swing, aura tick, spell or turret shot adds attack XP of its own any more",
		callers.is_empty(), callers)

	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar got: Array = []\nvar added: int = 0\n" \
		+ "func apply_server_attack(level: int, xp: int, xp_next: int) -> void:\n\tgot = [level, xp, xp_next]\n" \
		+ "func gain_attack_xp(amount: int) -> void:\n\tadded += amount\n" \
		+ "func gain_xp(_amount: int) -> void:\n\tpass\n"
	stub_script.reload()
	var killer: Node = stub_script.new()
	Combat._apply_xp(killer, {"xp_gained": 0, "attack_xp_gained": 25, "attack_level": 3,
		"attack_xp": 40, "attack_xp_to_next": 164})
	check("a kill's answer is copied onto the attack bar - level, XP and next - not added up",
		killer.got == [3, 40, 164] and killer.added == 0, [killer.got, killer.added])
	killer.got = []
	Combat._apply_xp(killer, {"xp_gained": 0, "attack_xp_gained": 25})
	check("an answer without those fields falls back to adding the amount, unscaled",
		killer.got.is_empty() and killer.added == 25, [killer.got, killer.added])
	killer.free()

	var body: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	body._set_stat_curve()
	var slots_before: Array = CharacterData.character_slots.duplicate(true)
	body.attack = 3
	body.attack_xp = 99
	body.apply_server_attack(3, 40, 164)
	check("a warrior's bar takes the server's numbers as they are (no 1.5 on top)",
		body.attack == 3 and body.attack_xp == 40 and body.attack_xp_next == 164,
		[body.attack, body.attack_xp, body.attack_xp_next])
	body.gain_attack_xp(10)
	check("and the fallback adds what it is given, no specialty, no AFK gate",
		body.attack_xp == 50, body.attack_xp)
	body.free()
	CharacterData.character_slots = slots_before

	# ---- a push that failed after it was accepted is retried -----------------
	var ss := ServerStorage.new()
	check("a fresh ServerStorage has nothing unpushed", not ss.has_unpushed())
	ss._record_push("status:0", false, "a")
	check("a refused push is remembered as unpushed", ss.has_unpushed())
	ss._record_push("status:0", true, "b")
	check("and cleared when that section goes through, with the new fingerprint",
		not ss.has_unpushed() and ss._last_pushed.get("status:0", "") == "b")
	ss._record_push("save:0", false, "c")
	check("  a failure is not recorded as pushed, so the retry sends it",
		not ss._last_pushed.has("save:0"))

	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nvar saves: int = 0\nvar unpushed: bool = true\n" \
		+ "func save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\tunpushed = false\n\treturn true\n" \
		+ "func has_unpushed() -> bool:\n\treturn unpushed\n"
	store_script.reload()
	var store = store_script.new()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	var was_clock: float = CharacterData._unpushed_clock
	CharacterData.storage = store
	CharacterData._save_pending = false
	CharacterData.flush_save()
	var flushed: int = store.saves
	CharacterData.flush_save()
	var again: int = store.saves
	store.unpushed = true
	CharacterData._unpushed_clock = 0.0
	CharacterData._process(0.016)
	var retried: int = store.saves
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending
	CharacterData._unpushed_clock = was_clock
	check("quitting with nothing queued but a failed push behind it writes the save",
		flushed == 1, flushed)
	check("  and once it is through, quitting again writes nothing", again == 1, again)
	check("  and a failed push is retried on its own clock, with nobody changing anything",
		retried == 2, retried)

	# ---- passwords: one rule ------------------------------------------------
	check("a password's surrounding spaces are not part of it",
		Api.clean_password("  hunter2hunter2 ") == "hunter2hunter2")
	var raw_fields: Array = []
	for path in ["res://src/ui/menus/loginmenu.gd", "res://src/ui/menus/optionsscreen.gd"]:
		for line in _code_src(path).split("\n"):
			if line.contains("password") and line.contains(".text") and line.contains("var ") \
					and not line.contains("clean_password("):
				raw_fields.append("%s: %s" % [path.get_file(), line.strip_edges()])
	check("every password field read goes through Api.clean_password - login, options, recovery",
		raw_fields.is_empty(), raw_fields)

	# ---- the gate spikes hit at full height -----------------------------------
	var frames_wrong: Array = []
	for el in ["", "earth", "fire", "ice", "light", "water", "wind"]:
		var node: Node = (load("res://scene/projectiles/%ssecondbossprojectile.tscn" % el) as PackedScene).instantiate()
		if int(node.get("impact_frame")) != 2:
			frames_wrong.append("%ssecondbossprojectile %s" % [el, node.get("impact_frame")])
		node.free()
	check("every gate spike lands on frame 2, the one its art holds at full height",
		frames_wrong.is_empty(), frames_wrong)
	var pillar: Node = (load("res://scene/projectiles/bossprojectile.tscn") as PackedScene).instantiate()
	check("and the pillar still on frame 1", int(pillar.get("impact_frame")) == 1, pillar.get("impact_frame"))
	pillar.free()
	check("  and the hit is timed by that setting, not a number typed in the script",
		_func_body(_code_src("res://src/projectiles/bossprojectile.gd"), "func _on_frame_changed(")
			.contains("anim.frame != impact_frame"))

	# ---- bosses are not shoved --------------------------------------------------
	check("a boss joins the group the wade query skips",
		_func_body(_code_src("res://src/enemies/bossenemy.gd"), "func _ready(").contains("add_to_group(&\"unpushable\")")
		and _code_src("res://src/characters/player.gd").contains("is_in_group(\"unpushable\")"))

	# ---- M opens the map ------------------------------------------------------
	var hud_input := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _unhandled_input(")
	var m_at := hud_input.find("is_action_pressed(\"minimap_toggle\")")
	check("M (minimap_toggle) opens the map, like I, C and G open theirs",
		m_at != -1 and hud_input.find("toggle_map()", m_at) != -1
		and InputMap.has_action("minimap_toggle"))

	# ---- the electric orb animates ------------------------------------------------
	var holder := Node2D.new()
	add_child(holder)
	var still: Array = []
	for el in ["", "dark", "earth", "ice", "light", "water", "wind"]:
		var orb: Node = (load("res://scene/projectiles/%smagicprojectile.tscn" % el) as PackedScene).instantiate()
		holder.add_child(orb)
		var sprite: AnimatedSprite2D = orb.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite == null or not sprite.is_playing():
			still.append("%smagicprojectile" % el)
	check("all seven electric orbs play their animation (they flew as a still frame)",
		still.is_empty(), still)
	holder.queue_free()

	# ---- an update is announced -------------------------------------------------
	var was_min: int = Api.server_min_build
	var was_current: int = Api.server_current_build
	Api.server_min_build = 0
	Api.server_current_build = Api.BUILD
	var current_note: String = Api.build_notice()
	Api.server_current_build = Api.BUILD + 1
	var newer_note: String = Api.build_notice()
	Api.server_min_build = Api.BUILD + 1
	var refused_note: String = Api.build_notice()
	Api.server_min_build = was_min
	Api.server_current_build = was_current
	check("a current build says nothing", current_note == "", current_note)
	check("a newer build on the server is announced", newer_note.contains("newer version"), newer_note)
	check("a refused build says it is too old", refused_note.contains("too old"), refused_note)
	check("and the login screen shows it once it has asked",
		_func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _check_connection_and_resume(").contains("build_notice()"))

	# ---- the revive price is read, not copied ------------------------------------
	var go: Node = (load("res://src/ui/menus/gameover.gd") as Script).new()
	check("the game-over screen's lusion price is GameConstants.REVIVE_COST",
		int(go.get("revive_cost")) == GameConstants.REVIVE_COST, go.get("revive_cost"))
	go.free()
	print("  sweep: attack, pushes, passwords, spikes, bosses, M, orbs, updates, price - all joined")


func _test_the_sweep_words() -> void:
	section("THE SWEEP — the words a player reads")

	check("counted() says 1 day, 3 days, 1,204 lusions",
		GameConstants.counted(1, "day") == "1 day" and GameConstants.counted(3, "day") == "3 days"
		and GameConstants.counted(1204, "lusion") == "1,204 lusions"
		and GameConstants.counted(2, "address", "addresses") == "2 addresses")
	var now := 1_800_000_000
	check("LocalTime.ago: just now, 5 min, 2 h, 1 day, 3 days - never '1 days' or '0 min'",
		LocalTime.ago(now - 20, now) == "just now" and LocalTime.ago(now - 300, now) == "5 min ago"
		and LocalTime.ago(now - 7200, now) == "2 h ago" and LocalTime.ago(now - 86400, now) == "1 day ago"
		and LocalTime.ago(now - 3 * 86400, now) == "3 days ago")
	var own_ago: Array = []
	for path in ["res://src/ui/friends/friendspanel.gd", "res://src/ui/staff/staffpanel.gd",
			"res://src/ui/guild/guildpanel.gd"]:
		if _code_src(path).contains("\"%d days ago\""):
			own_ago.append(path.get_file())
	check("the friends list, staff desk and guild roster ask LocalTime, not their own copy",
		own_ago.is_empty(), own_ago)

	var raw_areas: Array = []
	for id in AreaRegistry.AREAS:
		var shown: String = AreaRegistry.display_name(id)
		if shown == "" or (id in ["bossarena", "easteregg", "boss"] and shown == String(id).capitalize()):
			raw_areas.append("%s -> %s" % [id, shown])
	check("every area has a name a player reads (no 'Bossarena', no 'Easteregg')",
		raw_areas.is_empty() and AreaRegistry.AREA_NAMES.size() == AreaRegistry.AREAS.size(), raw_areas)
	var capitalised: Array = []
	for path in ["res://src/ui/menus/mapscreen.gd", "res://src/world/ladder.gd", "res://src/world/leavetown.gd",
			"res://src/ui/players/playerspanel.gd", "res://src/ui/trade/tradepanel.gd", "res://src/ui/guild/guildpanel.gd"]:
		for line in _code_src(path).split("\n"):
			if line.contains(".capitalize()") and (line.contains("area") or line.contains("where")
					or line.contains("get_basename()") or line.contains("_area")):
				capitalised.append("%s: %s" % [path.get_file(), line.strip_edges()])
	check("and no screen capitalises an area id itself", capitalised.is_empty(), capitalised)

	var sign_text := FileAccess.get_file_as_string("res://scene/interactables/sign.tscn")
	check("the town sign names the Crowned, not a Beholder the game does not have",
		sign_text.contains("slay the Crowned") and not sign_text.contains("Beholder"))
	var over := FileAccess.get_file_as_string("res://scene/ui/menus/gameover.tscn")
	check("the game-over screen reads GAME OVER and 'Return to character select'",
		over.contains("\"GAME OVER\"") and over.contains("\"Return to character select\""))

	var x_buttons: Array = []
	for path in _all_files_under("res://scene/ui", ".tscn"):
		if FileAccess.get_file_as_string(path).contains("text = \"x\"\n"):
			x_buttons.append(path.get_file())
	check("every close button is the same ×", x_buttons.is_empty(), x_buttons)

	var rods: Array = []
	for f in DirAccess.get_files_at("res://data/items/fishing"):
		if f.ends_with(".tres") and FileAccess.get_file_as_string("res://data/items/fishing/" + f).contains("Requires fishing level"):
			rods.append(f)
	check("no rod claims a fishing level it does not require (rods raise reach, they gate nothing)",
		rods.is_empty(), rods)

	var labels: Dictionary = (load("res://src/ui/kingdom/kingdomboard.gd") as Script).get_script_constant_map().get("REASON_LABELS", {})
	check("the kingdom board has words for founding a guild and gold taken back by staff",
		labels.has("guild_found") and labels.has("staff_gold"), labels.keys())

	var chat: Node = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate()
	check("the guild tab no longer says it is waiting on guilds",
		not chat._tab_hint("guild").contains("Waiting"), chat._tab_hint("guild"))
	check("  and a one-second wait is '1 second'", chat._readable_wait(1) == "1 second", chat._readable_wait(1))
	chat.free()

	var stats_code := _code_src("res://src/ui/statsscreen.gd")
	check("the stats screen shows a skill's progress as a percentage, not 'n/100'",
		not stats_code.contains("/100") and stats_code.contains("%d%%")
		and not FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn").contains("0/100"))
	check("  and says Health and Defence like the rest of the game",
		FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn").contains("\"Health:\"")
		and FileAccess.get_file_as_string("res://scene/ui/statsscreen.tscn").contains("\"Defence:\""))

	var talking: Array = []
	for path in ["res://src/ui/chat/chatpanel.gd", "res://src/ui/friends/friendspanel.gd", "res://src/ui/guild/guildpanel.gd"]:
		var code := _code_src(path)
		if code.contains("Is it running?") or not code.contains("no_answer_text()"):
			talking.append(path.get_file())
	check("chat, friends and guilds say 'no answer' in a player's words, not 'Is it running?'",
		talking.is_empty(), talking)

	var tip: Control = (load("res://scene/ui/inventory/itemtooltip.tscn") as PackedScene).instantiate()
	var sword := ItemData.new()
	sword.item_id = "sweeptest_sword"
	sword.damage = 32
	sword.bonus_damage_percent = 2
	check("a sword reads '32 Damage, +2% Damage Bonus', not '32 Damage, +2% Damage'",
		tip._requirement_lines(sword) == "32 Damage, +2% Damage Bonus", tip._requirement_lines(sword))
	tip.free()

	var inv_code := _code_src("res://src/ui/inventory/inventoryscreen.gd")
	check("the class refusal joins with 'or', like the tooltip ('Only warriors or tanks')",
		inv_code.contains("\" or \".join(names)"))
	check("the trash asks in its own words, not Godot's 'Please Confirm...'",
		_code_src("res://src/ui/inventory/trashslot.gd").contains("confirm_dialog.title = "))
	check("a shop row says the rarity and 'Armour', like the tooltip",
		_code_src("res://src/ui/shop/shopinventory.gd").contains("GameConstants.rarity_name("))
	print("  sweep: plurals, areas, sign, game over, ×, rods, board, chat, stats, errors, tooltip, shop")


# =============================================================================
# THE BROWSER BUILD
# =============================================================================
# Most of what the browser build needs can only be watched in a browser: it was
# (headless Chromium, the 4.6.1 web templates, the real API behind web/serve.py)
# and CLAUDE.md has what was measured. What is held here is every wire that a
# desktop run can see - the preset, the loader, the address, the rows a browser
# cannot use, the save a closing tab sends, and the one bug an export had that
# the editor never shows.

func _test_the_windows_build() -> void:
	section("THE WINDOWS BUILD - one file to hand out, without the suite in it")

	# Day 1: "we need that pc export - this game is not playable on a phone".
	# The project had a Web preset and nothing else. Exported and booted from
	# the sandbox: one 113 MB .exe, the pack inside it, every item and area
	# loaded, and nothing from src/tools or scene/tests stored.
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	var win := ""
	for sec in presets.get_sections():
		if str(presets.get_value(sec, "platform", "")) == "Windows Desktop":
			win = sec
	check("there is a Windows preset", win != "", presets.get_sections())
	if win == "":
		return
	var opts := win + ".options"
	var excluded: String = str(presets.get_value(win, "exclude_filter", ""))
	check("  the suite and the tools do not ship", excluded.contains("src/tools/*")
		and excluded.contains("scene/tests/*"), excluded)
	var out_path: String = str(presets.get_value(win, "export_path", ""))
	check("  it exports under builds/, which git ignores - an export holds the private art pack",
		out_path.begins_with("builds/") and out_path.ends_with(".exe")
		and FileAccess.get_file_as_string("res://.gitignore").contains("\nbuilds/"), out_path)
	check("  one file to hand out: the pack is inside the .exe",
		presets.get_value(opts, "binary_format/embed_pck", false) == true)
	check("  64-bit", str(presets.get_value(opts, "binary_format/architecture", "")) == "x86_64")
	check("  named Elusion RPG, by Elusion Studios",
		str(presets.get_value(opts, "application/product_name", "")) == "Elusion RPG"
		and str(presets.get_value(opts, "application/company_name", "")) == "Elusion Studios")
	# THE VERSION WINDOWS SHOWS IS THE GAME'S OWN. Api.DISPLAY_VERSION is the
	# one players read; a release that bumps it and not this would show an old
	# number in the file's properties.
	var version: String = str(presets.get_value(opts, "application/file_version", ""))
	check("  and its version is the game's (Api.DISPLAY_VERSION)",
		version.begins_with(Api.DISPLAY_VERSION + ".") or version == Api.DISPLAY_VERSION,
		[version, Api.DISPLAY_VERSION])
	print("  windows: one .exe, the suite left out, the game's own name and version")


func _test_the_browser_build() -> void:
	section("THE BROWSER BUILD — one address, a loader, and a tab that can close")

	# ---- the preset ------------------------------------------------------------
	var presets := ConfigFile.new()
	var read_err: int = presets.load("res://export_presets.cfg")
	check("export_presets.cfg is in the project", read_err == OK, read_err)
	var web := ""
	for sec in presets.get_sections():
		if str(presets.get_value(sec, "platform", "")) == "Web":
			web = sec
	check("it has a Web preset", web != "", presets.get_sections())
	var opts := web + ".options"
	check("  built without threads: a threaded export needs isolation headers, and it took "
		+ "40 s to reach the town in Chromium against 4.4 s without",
		presets.get_value(opts, "variant/thread_support", true) == false)
	var shell: String = str(presets.get_value(opts, "html/custom_html_shell", ""))
	check("  with Elusion's own loader as its page", shell == "res://web/shell.html"
		and FileAccess.file_exists(shell), shell)
	check("  and no service worker: one would serve yesterday's build from its cache after a refresh",
		presets.get_value(opts, "progressive_web_app/enabled", true) == false)
	var excluded: String = str(presets.get_value(web, "exclude_filter", ""))
	check("  the suite and the tools do not ship", excluded.contains("src/tools/*")
		and excluded.contains("scene/tests/*"), excluded)
	var out_path: String = str(presets.get_value(web, "export_path", ""))
	check("  and it exports under builds/, which git ignores - an export holds the private art pack",
		out_path.begins_with("builds/") and FileAccess.get_file_as_string("res://.gitignore").contains("\nbuilds/"),
		out_path)

	# ---- the loader --------------------------------------------------------------
	var page: String = FileAccess.get_file_as_string("res://web/shell.html")
	var missing_names: Array = []
	for placeholder in ["$GODOT_URL", "$GODOT_CONFIG", "$GODOT_THREADS_ENABLED", "$GODOT_HEAD_INCLUDE"]:
		if not page.contains(placeholder):
			missing_names.append(placeholder)
	check("the loader carries every name the exporter fills in", missing_names.is_empty(), missing_names)
	check("  and steps aside when the game says it is drawing (window.elusionReady)",
		page.contains("window.elusionReady = "))
	check("  and gives the tab back its name then - the engine renames it after the project",
		page.contains("const pageTitle = document.title;") and page.contains("document.title = pageTitle;"))
	var art_at: int = page.find("data:image/png;base64,")
	var art_end: int = page.find("\"", art_at)
	var embedded: PackedByteArray = Marshalls.base64_to_raw(
		page.substr(art_at + 22, art_end - art_at - 22)) if art_at != -1 else PackedByteArray()
	check("  its picture is the login screen's own (art/menu/original size.png) - re-embed it if that changes",
		embedded == FileAccess.get_file_as_bytes("res://art/menu/original size.png"), embedded.size())
	var login_code := _code_src("res://src/ui/menus/loginmenu.gd")
	var login_ready := _func_body(login_code, "func _ready()")
	check("the login screen tells the loader once it has drawn, in a browser",
		login_ready.contains("WebPage.in_browser()") and login_ready.contains("WebPage.mark_ready()")
		and login_ready.contains("frame_post_draw"))

	# ---- one address -------------------------------------------------------------
	check("a page's origin is the API's address",
		Api.web_base_url("https://play.example.com") == "https://play.example.com"
		and Api.web_base_url("http://localhost:8060/") == "http://localhost:8060",
		Api.web_base_url("http://localhost:8060/"))
	check("  and a page from disk (origin \"null\") or no page at all is no address",
		Api.web_base_url("null") == "" and Api.web_base_url("") == ""
		and Api.web_base_url("file://") == "")
	var api_code := _code_src("res://src/systems/api.gd")
	var resolve := _func_body(api_code, "static func _resolve_base_url()")
	check("  asked for first in a browser, before any override that cannot work there",
		resolve.find("OS.has_feature(\"web\")") != -1
		and resolve.find("OS.has_feature(\"web\")") < resolve.find("get_cmdline_args()")
		and resolve.contains("WebPage.origin()"))

	# ---- off the web, nothing happens --------------------------------------------
	var WebPageScript: Script = load("res://src/systems/webpage.gd")
	check("the page helper does nothing on the desktop",
		not WebPageScript.in_browser() and WebPageScript.origin() == ""
		and WebPageScript.watch_leaving(func() -> void: pass).is_empty()
		and not WebPageScript.send_now("http://x", "PUT", PackedStringArray(), "{}"))
	check("  and neither does a send meant for a closing page",
		not Api.send_before_leaving("PUT", "/api/save", {}))

	# ---- rows a browser cannot use ---------------------------------------------
	var Options: Script = load("res://src/ui/menus/optionsscreen.gd")
	var on_web: Array = Options.rows_hidden_on("Web")
	check("in a browser, Options drops window size, V-Sync, the renderer and the graphics API",
		on_web.has("window") and on_web.has("vsync") and on_web.has("renderer") and on_web.has("api"),
		on_web)
	check("  on Windows it drops nothing, elsewhere only the graphics API",
		Options.rows_hidden_on("Windows").is_empty() and Options.rows_hidden_on("Linux") == ["api"],
		[Options.rows_hidden_on("Windows"), Options.rows_hidden_on("Linux")])
	var screen: Node = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate()
	screen.api_row = screen.get_node("%apirow")
	screen.window_size = screen.get_node("%windowsize")
	screen.vsync_mode = screen.get_node("%vsyncmode")
	screen.renderer = screen.get_node("%renderer")
	screen.renderer_note = screen.get_node("%renderernote")
	screen._hide_rows_for("Web")
	var still_shown: Array = []
	for row in [screen.get_node("%windowsize").get_parent(), screen.get_node("%vsyncmode").get_parent(),
			screen.get_node("%renderer").get_parent(), screen.get_node("%renderernote"), screen.get_node("%apirow")]:
		if (row as CanvasItem).visible:
			still_shown.append(str(row.name))
	check("  and the screen really hides those rows", still_shown.is_empty(), still_shown)
	check("  but keeps fullscreen and the frame cap, which a browser honours",
		(screen.get_node("%fullscreentoggle").get_parent() as CanvasItem).visible
		and (screen.get_node("%framecap").get_parent() as CanvasItem).visible)
	screen.free()
	var report := {"refresh": -1.0, "fps": 59.6, "vsync": "on", "cap": 0, "overridden": false}
	check("  its readout says the browser paces the frames, not 'Screen ? Hz - V-Sync on'",
		Options.pacing_line(report, "Web") == "Drawing 60 fps  -  paced by the browser",
		Options.pacing_line(report, "Web"))
	check("  and on the desktop reads as it did",
		Options.pacing_line({"refresh": 60.0, "fps": 60.0, "vsync": "on", "cap": 144, "overridden": false}, "Windows")
			== "Screen 60 Hz  -  drawing 60 fps  -  V-Sync on, cap 144",
		Options.pacing_line({"refresh": 60.0, "fps": 60.0, "vsync": "on", "cap": 144, "overridden": false}, "Windows"))
	var login: Node = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate()
	login._hide_exit_row()
	check("the login screen's Exit row and the rule above it go in a browser (a page cannot close its tab)",
		not (login.get_node("%exitbutton").get_parent() as CanvasItem).visible
		and not (login.get_node("centercontainer/mainpanel/margincontainer/vboxcontainer/hseparator2") as CanvasItem).visible
		and (login.get_node("%loginbutton") as CanvasItem).visible)
	login.free()
	check("  and only there", login_ready.find("_hide_exit_row()") > login_ready.find("if WebPage.in_browser():")
		and login_ready.find("if WebPage.in_browser():") != -1)

	# ---- a closing tab still saves ---------------------------------------------
	var ss := ServerStorage.new()
	var slot := {"character": "warrior", "level": 5, "hp": 40, "max_hp": 60,
		"inventory": [{"item_id": "healthpotion", "quantity": 2}, null],
		"explored": {"field": "abc"}, "area": "field"}
	var payload := {"character_slots": [slot, null, null, null],
		"account_data": {"lusions": 3, "bank_inventory": []}}
	var first: Array = ss.requests_before_leaving(payload)
	var paths: Array = first.map(func(r: Dictionary) -> String: return str(r["path"]))
	check("a closing page sends every section the server has not confirmed",
		paths.size() == 3 and paths.has("/api/player/status")
		and paths.has("/api/account/lusions") and paths.has("/api/save"),
		paths)
	check("  and neither the bag nor the bank - they are the server's",
		not paths.has("/api/character/inventory") and not paths.has("/api/account/bank"), paths)
	check("  the save last and without the explored map (64 KB of keepalive, and the map can fill it)",
		not paths.is_empty() and paths[-1] == "/api/save" and not (first[-1]["body"] as Dictionary).has("explored")
		and (first[-1]["body"] as Dictionary).get("area", "") == "field",
		first[-1]["body"] if not first.is_empty() else {})
	check("  as PUTs", first.all(func(r: Dictionary) -> bool: return r["method"] == "PUT"))
	check("  and not twice when the page hides and then unloads",
		ss.requests_before_leaving(payload).is_empty())
	var fp := JSON.stringify(ss._status_body(0, slot))
	ss._record_push("status:0", true, fp)
	slot["hp"] = 30
	var again: Array = ss.requests_before_leaving(payload)
	check("  vitals changed since go again, and only the vitals",
		again.size() == 1 and again[0]["path"] == "/api/player/status", again)
	var hurt := JSON.stringify(ss._status_body(0, slot))
	ss._record_push("status:0", true, hurt)
	ss._record_push("status:0", true, "the server moved on to other vitals")
	slot["hp"] = 40
	var back: Array = ss.requests_before_leaving(payload)
	check("  a confirmed push clears the mark, so vitals put back as they were are not taken for sent",
		back.size() == 1 and back[0]["path"] == "/api/player/status", back)
	slot["inventory"] = [null, {"item_id": "healthpotion", "quantity": 2}]
	check("  and a bag changed since sends nothing at all",
		ss.requests_before_leaving(payload).is_empty())
	var ss_code := _code_src("res://src/systems/serverstorage.gd")
	check("  it reads the same section lists a push walks, so the two cannot disagree",
		_func_body(ss_code, "func _push_slot(").contains("_slot_sections(index, slot)")
		and _func_body(ss_code, "func _push_account(").contains("_account_sections(account)")
		and _func_body(ss_code, "func requests_before_leaving(").contains("_slot_sections(index, slot)"))

	var leave_script := GDScript.new()
	leave_script.source_code = "extends SaveStorage\nvar asked: int = 0\nvar saves: int = 0\n" \
		+ "func requests_before_leaving(_payload: Dictionary) -> Array:\n\tasked += 1\n\treturn []\n" \
		+ "func save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\treturn true\n"
	leave_script.reload()
	var store = leave_script.new()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	CharacterData.storage = store
	CharacterData._save_pending = false
	CharacterData._on_page_leaving()
	var asked_idle: int = store.asked
	CharacterData._save_pending = true
	CharacterData._on_page_leaving()
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending
	check("CharacterData asks for them on leaving even with nothing queued (a push in flight dies with the tab)",
		asked_idle == 1, asked_idle)
	check("  and flushes the queued save as well, for a page that comes back",
		store.asked == 2 and store.saves == 1, [store.asked, store.saves])
	var cd_code := _code_src("res://src/systems/characterdata.gd")
	check("  it is watching: _ready() hands _on_page_leaving to the page",
		_func_body(cd_code, "func _ready()").contains("WebPage.watch_leaving(_on_page_leaving)"))
	check("  and each request goes out through Api.send_before_leaving()",
		_func_body(cd_code, "func _on_page_leaving()").contains("Api.send_before_leaving("))

	# ---- nothing loads ahead where it would be the wait itself -------------------
	check("this build loads areas in the background (a desktop build has threads)",
		AreaRegistry.loads_in_background())
	var ar_code := _code_src("res://src/systems/arearegistry.gd")
	var prefetch_body := _func_body(ar_code, "func prefetch(")
	check("  a build without threads asks for nothing ahead - there the request IS the load",
		ar_code.contains("not OS.has_feature(\"nothreads\")")
		and prefetch_body.find("if not loads_in_background():") != -1
		and prefetch_body.find("if not loads_in_background():") < prefetch_body.find("_start_prefetch("))
	var enter := _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _enter_world(")
	var gate := "if not AreaRegistry.is_ready(WORLD_AREA):"
	var first_gate := enter.find(gate)
	var second_gate := enter.find(gate, first_gate + 1) if first_gate != -1 else -1
	var takes := enter.find("AreaRegistry.scene_for(WORLD_AREA)")
	var drawn := enter.find("await get_tree().process_frame", second_gate) if second_gate != -1 else -1
	check("  so character select says 'Loading the world...' whenever the town is not ready - not only while it loads",
		first_gate != -1 and enter.substr(first_gate, gate.length() + 24).contains("_show_loading(idx)"))
	check("  and lets that label draw before a load that holds the screen - two frames, the first is the click's own",
		second_gate != -1 and drawn != -1 and drawn < takes
		and enter.substr(second_gate, drawn - second_gate).contains("in 2:"), [first_gate, second_gate, drawn, takes])

	# ---- the bug an export had and the editor never showed ------------------------
	var walkers: Array = []
	for path in _all_gd_under("res://src"):
		if path.begins_with("res://src/tools/"):
			continue
		if _code_src(path).contains("list_dir_begin("):
			walkers.append(path.get_file())
	check("nothing that ships walks res:// with DirAccess - an export lists every .tres as .tres.remap",
		walkers.is_empty(), walkers)
	check("  the item registry lists with ResourceLoader.list_directory(), which gives the editor's names",
		_func_body(_code_src("res://src/systems/itemregistry.gd"), "func _scan_folder(").contains("ResourceLoader.list_directory("))

	# ---- an arrival draws the right map from its first frame -----------------
	var player_code := _code_src("res://src/characters/player.gd")
	check("the player puts its camera in place at once - it runs on the physics clock, and "
		+ "an area's first frame came before the first tick (the map from its corner, unzoomed)",
		_func_body(player_code, "func snap_camera(").contains("force_update_scroll()")
		and _func_body(player_code, "func _ready(").contains("snap_camera()"))
	var place := _func_body(ar_code, "func place_player(")
	check("  a placed player is told so after the position, then the camera follows",
		place.find("global_position = spawn_position") != -1
		and place.find("reset_physics_interpolation()") > place.find("global_position = spawn_position")
		and place.find("snap_camera()") > place.find("reset_physics_interpolation()"))
	var field_code := _func_body(_code_src("res://src/world/field.gd"), "func _position_player_at_spawn(")
	var tele_code := _func_body(_code_src("res://src/world/teleporter.gd"), "func _on_body_entered(")
	check("  and so do the field's arrival portal and an in-world teleporter",
		field_code.find("snap_camera()") > field_code.find("player.reset_physics_interpolation()")
		and field_code.find("player.reset_physics_interpolation()") != -1
		and tele_code.find("snap_camera()") > tele_code.find("body.reset_physics_interpolation()")
		and tele_code.find("body.reset_physics_interpolation()") != -1)
	# BLACK AT RUNTIME, NOT IN project.godot. Set there, the editor drew every
	# gap in every tile black as well; see the MAP BACKDROP section.
	check("  and a frame with no scene in it yet is black, not the engine's grey",
		RenderingServer.get_default_clear_color().is_equal_approx(Color(0, 0, 0, 1)),
		RenderingServer.get_default_clear_color())

	# ---- pictures in chat, the browser's way ------------------------------------
	var Chat: Script = load("res://src/ui/chat/chatpanel.gd")
	check("in a browser the chat box points at + and dropping a file, not Ctrl+V (a page gets no pictures from the clipboard)",
		Chat.entry_placeholder(true).contains("drop") and not Chat.entry_placeholder(true).contains("Ctrl+V")
		and Chat.entry_placeholder(false).contains("Ctrl+V"))
	var chat_code := _code_src("res://src/ui/chat/chatpanel.gd")
	var image_pressed := _func_body(chat_code, "func _on_image_pressed(")
	check("  + asks the browser's own picker there, before any FileDialog (which shows the engine's empty virtual disk)",
		image_pressed.find("if WebPage.in_browser():") != -1
		and image_pressed.find("WebPage.pick_file(") > image_pressed.find("if WebPage.in_browser():")
		and image_pressed.find("WebPage.pick_file(") < image_pressed.find("FileDialog.new()"))
	var picked := _func_body(chat_code, "func _on_web_file_picked(")
	check("  and a picked file is attached exactly as a dropped one is",
		picked.find("store_buffer(bytes)") != -1 and picked.find("_attach_file(path)") > picked.find("store_buffer(bytes)"))
	check("  the picker does nothing on the desktop",
		WebPageScript.pick_file(".png", func(_b: PackedByteArray, _n: String) -> void: pass).is_empty())

	# ---- a ticked box under the pointer ----------------------------------------
	# Seen in the browser first, true everywhere: the theme had no hover_pressed
	# style, so a toggled button under the mouse fell back to the engine's own -
	# no border, the text pushed right, and "Remember me" read "Remember m".
	var ui_theme: Theme = load("res://assets/themes/rpg_ui_theme.tres")
	check("a pressed button under the pointer keeps the game's pressed look (no engine fallback)",
		ui_theme.has_stylebox("hover_pressed", "Button")
		and ui_theme.get_stylebox("hover_pressed", "Button") == ui_theme.get_stylebox("pressed", "Button")
		and ui_theme.has_color("font_hover_pressed_color", "Button")
		and ui_theme.get_color("font_hover_pressed_color", "Button") == ui_theme.get_color("font_pressed_color", "Button"))
	print("  browser: preset, loader, one address, rows, a closing tab, no loading ahead, the registry, arrivals, chat pictures, theme")


# =============================================================================
# LEAVING WAITS FOR THE SAVE
# =============================================================================
# flush_save() STARTS a push. Closing the window quit in the same frame (a bag
# changed and closed at once kept its old bag on the real server), and a logout
# raced its revoke against the push. Both now wait, bounded, for the server.

func _test_leaving_waits_for_the_save() -> void:
	section("LEAVING — closing the window and logging out wait for the save")

	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nvar saves: int = 0\nvar left: int = 0\n" \
		+ "func save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\treturn true\n" \
		+ "func is_pushing() -> bool:\n\tleft -= 1\n\treturn left > 0\n"
	store_script.reload()
	var store = store_script.new()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	CharacterData.storage = store
	CharacterData._save_pending = true
	store.left = 6
	var all_went: bool = await CharacterData.finish_saving(5.0)
	check("finish_saving() writes the queued save and waits until the push is through",
		store.saves == 1 and store.left <= 0 and all_went, [store.saves, store.left, all_went])

	store.left = 1_000_000
	var t0 := Time.get_ticks_msec()
	var stuck_went: bool = await CharacterData.finish_saving(0.2)
	var waited: int = Time.get_ticks_msec() - t0
	check("  and gives up on a server that never answers, at the limit it was given",
		not stuck_went and waited >= 180 and waited < 1500, [stuck_went, waited])

	store.left = 5
	CharacterData._save_pending = true
	var quit_state: Array = []
	var fake_quit := func() -> void: quit_state.append(store.left)
	CharacterData._quitting = false
	await CharacterData._quit_after_saving(fake_quit)
	check("closing the window quits only once the push is through",
		quit_state.size() == 1 and int(quit_state[0]) <= 0 and store.saves == 2, [quit_state, store.saves])
	await CharacterData._quit_after_saving(fake_quit)
	check("  and a second press of the X does not quit twice", quit_state.size() == 1, quit_state)
	CharacterData._quitting = false
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending

	var cd_code := _code_src("res://src/systems/characterdata.gd")
	check("the engine no longer quits on the X by itself",
		_func_body(cd_code, "func _ready()").contains("set_auto_accept_quit(false)"))
	var notif := _func_body(cd_code, "func _notification(")
	check("  the X goes to _quit_after_saving()", notif.find("NOTIFICATION_WM_CLOSE_REQUEST") != -1
		and notif.find("_quit_after_saving()") > notif.find("NOTIFICATION_WM_CLOSE_REQUEST"))
	var quitting := _func_body(cd_code, "func _quit_after_saving(")
	check("  which takes the live character's state first, as a logout does",
		quitting.find("save_character_state(player)") != -1
		and quitting.find("save_character_state(player)") < quitting.find("finish_saving("))

	var logout := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _on_logout_pressed(")
	var waits := logout.find("await CharacterData.finish_saving()")
	check("a logout waits for the save before it clears the session and revokes the token",
		waits != -1 and waits < logout.find("CharacterData.clear_current_user()")
		and waits < logout.find("await Api.logout()"))
	check("ServerStorage says when a push is still on its way",
		ServerStorage.new().is_pushing() == false
		and _func_body(_code_src("res://src/systems/serverstorage.gd"), "func is_pushing(").contains("_has_queued"))
	print("  leaving: finish_saving, the X, a second X, logout order")


# =============================================================================
# SHOWN SKILL XP ROUNDS LIKE THE SERVER
# =============================================================================
# The server grants int(raw x specialty) per batch SkillTrainer sends
# (proficient_amount() in app.py). The bar used to round each hit, with a floor
# of 1, so a tank's 1-point hits showed 1 against the server's 1.5.

func _test_skill_xp_rounds_like_the_server() -> void:
	section("SKILL XP — the bar rounds a batch the way the server grants it")

	var trainer: Node = (load("res://src/systems/skilltrainer.gd") as Script).new()
	var shown := 0
	var steps: Array = []
	for i in 10:
		var step: int = trainer.report("defense", 1, 1.5)
		steps.append(step)
		shown += step
	check("ten 1-point hits at a tank's 1.5 show 15, the server's int(10 x 1.5) - not 10",
		shown == 15 and steps.min() >= 1 and steps.max() <= 2, [shown, steps])
	var magic := 0
	for i in 7:
		magic += trainer.report("magic", 3, 1.5)
	check("  seven 3-point spells show 31, int(21 x 1.5) - not 28, rounding each",
		magic == 31, magic)
	check("  and a hit worth nothing shows nothing (it used to show 1)",
		trainer.report("defense", 0, 1.5) == 0)
	var plain := 0
	for i in 5:
		plain += trainer.report("agility", 7)
	check("  with no specialty, what is shown is what was earned", plain == 35, plain)
	check("  and the raw amounts are what waits for the server",
		int(trainer._pending["defense"]) == 10 and int(trainer._pending["magic"]) == 21
		and int(trainer._pending["agility"]) == 35, trainer._pending)
	trainer.free()

	var flush := _func_body(_code_src("res://src/systems/skilltrainer.gd"), "func flush(")
	check("a flushed batch starts the rounding again, as the server does per batch",
		flush.find("_shown = {") != -1 and flush.find("_shown = {") < flush.find("await Api.post("))
	var player_code := _code_src("res://src/characters/player.gd")
	var defense := _func_body(player_code, "func gain_defense_xp(")
	var magic_body := _func_body(player_code, "func gain_magic_xp(")
	check("defence and magic show what SkillTrainer answers, with the class specialty",
		defense.contains("SkillTrainer.report(\"defense\", amount,") and magic_body.contains("SkillTrainer.report(\"magic\", amount,")
		and not defense.contains("maxi(1, int(amount") and not magic_body.contains("maxi(1, int(amount"))
	print("  skill xp: batch rounding, zero, no specialty, raw pending, flush, callers")



func _test_game_keys_are_not_menu_keys() -> void:
	section("GAME KEYS — walking and attacking do not work a clicked menu")

	# project.godot binds WASD and the arrows to ui_left/right/up/down as well
	# as the move_ actions, and Space to ui_accept as well as attack. So a
	# control that kept the focus from a click took every step as menu
	# navigation. Built here the way a panel is: two buttons in a column, a
	# slider and a text box, on a layer of their own.
	var HUD: Script = load("res://src/ui/characterhud.gd") as Script
	var layer := CanvasLayer.new()
	var column := VBoxContainer.new()
	var first := Button.new()
	first.text = "first"
	var second := Button.new()
	second.text = "second"
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.5
	slider.custom_minimum_size = Vector2(120, 16)
	var box := LineEdit.new()
	box.custom_minimum_size = Vector2(120, 24)
	for node in [first, second, slider, box]:
		column.add_child(node)
	layer.add_child(column)
	add_child(layer)
	# A frame, so the column has laid out: focus moves by position.
	await get_tree().process_frame
	await get_tree().process_frame
	var presses := [0]
	first.pressed.connect(func() -> void: presses[0] += 1)
	var viewport: Viewport = get_viewport()

	# A stand-in for the HUD's _input: the real HUD cannot join the tree here,
	# since its _ready() starts the server polls. Its _input is one call to the
	# static below, checked by text at the end.
	var hand_back := GDScript.new()
	hand_back.source_code = "extends Node\nvar hud: Script\n" \
		+ "func _input(event: InputEvent) -> void:\n\thud.release_for_world_key(event, get_viewport())\n"
	hand_back.reload()

	var press := func(code: Key, unicode: int = 0) -> void:
		for down in [true, false]:
			var key := InputEventKey.new()
			key.keycode = code
			key.physical_keycode = code
			key.unicode = unicode
			key.pressed = down
			viewport.push_input(key)

	# ---- WITHOUT IT: the bug, reproduced, so the checks below mean something ----
	first.grab_focus()
	press.call(KEY_S)
	var moved_to: Control = viewport.gui_get_focus_owner()
	first.grab_focus()
	press.call(KEY_SPACE, 32)
	slider.grab_focus()
	press.call(KEY_D)
	check("without it, S walks the focus down the column, Space presses the button, D turns the slider",
		moved_to == second and presses[0] == 1 and slider.value > 0.5,
		[moved_to.name if moved_to else "nobody", presses[0], slider.value])

	# ---- WITH IT ----
	var watcher := Node.new()
	watcher.set_script(hand_back)
	watcher.hud = HUD
	add_child(watcher)
	presses[0] = 0
	slider.value = 0.5
	first.grab_focus()
	press.call(KEY_S)
	check("a step takes the focus off a clicked button instead of moving it",
		viewport.gui_get_focus_owner() == null, viewport.gui_get_focus_owner())
	first.grab_focus()
	press.call(KEY_DOWN)
	check("  the arrow keys as well", viewport.gui_get_focus_owner() == null)
	first.grab_focus()
	press.call(KEY_SPACE, 32)
	check("Space attacks and presses nothing", presses[0] == 0, presses[0])
	slider.grab_focus()
	press.call(KEY_D)
	press.call(KEY_RIGHT)
	check("walking right leaves a clicked slider where it was", is_equal_approx(slider.value, 0.5), slider.value)
	box.grab_focus()
	press.call(KEY_W, 119)
	press.call(KEY_SPACE, 32)
	press.call(KEY_D, 100)
	check("a text box keeps the keyboard: the keys are letters there",
		viewport.gui_get_focus_owner() == box and box.text == "w d", [box.text])
	box.editable = false
	box.grab_focus()
	press.call(KEY_A, 97)
	check("  but not one that cannot be typed in", viewport.gui_get_focus_owner() == null)
	first.grab_focus()
	press.call(KEY_ENTER)
	press.call(KEY_TAB)
	check("Enter and Tab are not game keys, so the menu keeps them",
		viewport.gui_get_focus_owner() != null)

	var sprint_up := InputEventKey.new()
	sprint_up.keycode = KEY_W
	sprint_up.physical_keycode = KEY_W
	sprint_up.shift_pressed = true
	sprint_up.pressed = true
	var interact := InputEventKey.new()
	interact.keycode = KEY_E
	interact.physical_keycode = KEY_E
	interact.pressed = true
	check("Shift+W, sprinting up, is still a step; E is not one of them",
		HUD.is_world_key(sprint_up) and not HUD.is_world_key(interact))

	watcher.queue_free()
	layer.queue_free()

	var input_body := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _input(")
	check("the HUD's _input hands the keyboard back",
		input_body.contains("release_for_world_key(event, get_viewport())"), input_body.strip_edges())
	print("  game keys: the bug, buttons, arrows, space, slider, text boxes, other keys, the wiring")


func _test_staff_logins_take_a_code() -> void:
	section("STAFF LOGIN CODE — the password, then the code from the email")

	# ---- what counts as the code step ----
	var first_step := {"ok": true, "status": 202, "error": "",
		"data": {"code_required": true, "sent_to": "b***s@example.test", "expires_in": 900}}
	var wrong_code := {"ok": false, "status": 400, "error": "That code is not right.",
		"data": {"error": "Bad Code", "code_required": true, "sent_to": "b***s@example.test",
			"message": "That code is not right, or it has run out."}}
	var logged_in := {"ok": true, "status": 200, "error": "", "data": {"token": "t", "username": "boss"}}
	var wrong_password := {"ok": false, "status": 401, "error": "Incorrect username or password.", "data": {}}
	check("the first step (202) and a wrong code (400) are the code step; a login and a 401 are not",
		Api.needs_login_code(first_step) and Api.needs_login_code(wrong_code)
		and not Api.needs_login_code(logged_in) and not Api.needs_login_code(wrong_password))
	var api_login := _func_body(_code_src("res://src/systems/api.gd"), "func login(")
	check("Api.login sends the code, and never adopts a 202 - a 2xx with no token",
		api_login.contains("body[\"code\"] = code")
		and api_login.contains("if res.ok and not needs_login_code(res):"), api_login.left(400))

	# ---- the login screen ----
	var login: Node = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate()
	login._build_code_box()
	var box: LineEdit = login.login_code_box
	var form: Node = login.get_node("%loginform")
	var password: Node = login.get_node("%passwordlineedit")
	check("the code box is built hidden, right under the password",
		box != null and not box.visible and box.get_parent() == form
		and box.get_index() == password.get_index() + 1)
	login._show_code_step("boss", first_step)
	var said: Label = login.get_node("%errorlabel")
	check("a 202 shows the box and says where the code went, in the working grey",
		box.visible and said.text.contains("b***s@example.test")
		and said.get_theme_color("font_color") == login.SAY_WORKING, said.text)
	box.text = "183 774"
	check("  the typed code goes with the login, spaces out", login._typed_login_code("boss") == "183774",
		login._typed_login_code("boss"))
	check("  but only for the account it was asked for", login._typed_login_code("someoneelse") == "")
	login._show_code_step("boss", wrong_code)
	check("a wrong code keeps the box and what was typed, and says so in red",
		box.visible and box.text == "183 774" and said.text.contains("not right")
		and said.get_theme_color("font_color") == login.SAY_REFUSED, said.text)
	login.get_node("%usernamelineedit").text_changed.emit("somebody")
	check("changing the username puts the box away", not box.visible and box.text == ""
		and login._typed_login_code("boss") == "")
	login.free()

	var pressed := _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _on_login_button_pressed(")
	var step_at := pressed.find("if ApiScript.needs_login_code(res):")
	check("the button sends the typed code, and checks for the code step before res.ok and the 401",
		pressed.contains("Api.login(username, password, _typed_login_code(username))")
		and step_at != -1 and step_at < pressed.find("if res.ok:")
		and step_at < pressed.find("if res.status == 401:"), step_at)

	# ---- a staff login that needed no code is told, once ----
	var was := [Api.staff_unprotected, Api._told_staff_unprotected, Api.role]
	Api.staff_unprotected = true
	Api._told_staff_unprotected = false
	Api.role = "mod"
	var first_time: bool = Api.take_staff_unprotected_notice()
	var second_time: bool = Api.take_staff_unprotected_notice()
	Api._told_staff_unprotected = false
	Api.role = "player"
	var as_player: bool = Api.take_staff_unprotected_notice()
	Api.staff_unprotected = was[0]
	Api._told_staff_unprotected = was[1]
	Api.role = was[2]
	check("a staff login without a code is told once per login, and a player never",
		first_time and not second_time and not as_player, [first_time, second_time, as_player])
	var adopt := _func_body(_code_src("res://src/systems/api.gd"), "func _adopt_session(")
	var hud_ready := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(")
	check("  the flag comes from the login, and the HUD asks on its way in",
		adopt.contains("staff_unprotected = bool(data.get(\"staff_unprotected\", false))")
		and hud_ready.contains("_warn_unprotected_staff()"))
	print("  staff code: the step, the adopt gate, the box, the order, the once-only notice")


func _test_chat_is_one_line_per_message() -> void:
	section("CHAT - one message is one line, with nothing invisible in it")

	var ChatPanel: Script = load("res://src/ui/chat/chatpanel.gd") as Script
	check("the chat panel script loads", ChatPanel != null and ChatPanel.can_instantiate())
	if ChatPanel == null or not ChatPanel.can_instantiate():
		return
	check("newlines are spaces: 150 of them used to be 150 blank lines on every screen",
		ChatPanel.one_line("top" + "\n".repeat(150) + "bottom") == "top bottom")
	check("  so a player cannot put a fake [SERVER] line on a line of its own",
		not ChatPanel.one_line("hi\n12:00 [SERVER] restarting").contains("\n"))
	check("a bidi override and zero-width characters are dropped",
		ChatPanel.one_line(String.chr(0x202E) + "evil" + String.chr(0x200B) + String.chr(0xFEFF)) == "evil")
	check("  and a message of nothing else comes out empty",
		ChatPanel.one_line(String.chr(0x200B) + String.chr(0x2060)) == "")
	var family: String = String.chr(0x1F468) + String.chr(0x200D) + String.chr(0x1F469)
	check("emoji joined with ZWJ keep the joiner", ChatPanel.one_line(family + " hi") == family + " hi")
	check("tabs and runs of spaces are one space", ChatPanel.one_line("a\t\t b   c") == "a b c")

	# THE REAL LINE, as the log builds it - not the helper alone.
	var chat: Node = ChatPanel.new()
	var label: RichTextLabel = chat._node_for({"kind": "chat", "by": "griefer", "role": "player",
		"body": "hi\n\n\n\n12:00 [SERVER] Server restarting", "at": 1700000000}) as RichTextLabel
	var drawn: String = label.get_parsed_text() if label != null else ""
	check("a chat line is drawn as one line, and the [ stays a literal bracket",
		label != null and not drawn.contains("\n") and drawn.contains("hi 12:00 [SERVER] Server restarting"), drawn)
	var picture: Control = chat._node_for({"kind": "image", "by": "griefer", "role": "player",
		"image": "", "body": "look\n\n\nhere", "at": 1700000000})
	var header: RichTextLabel = null
	if picture != null:
		for child in picture.get_children():
			if child is RichTextLabel:
				header = child
				break
	check("  and so is a picture's caption", header != null and header.get_parsed_text().contains("look here")
		and not header.get_parsed_text().contains("\n"), header.get_parsed_text() if header else "")
	if label != null:
		label.free()
	if picture != null:
		picture.free()
	chat.free()
	print("  chat lines: newlines, fake server lines, invisible characters, emoji, spaces, the drawn line, captions")


func _test_chat_keeps_your_place() -> void:
	section("CHAT - a new line is added, not the log rebuilt; reading up stays put")

	var packed: PackedScene = load("res://scene/ui/chat/chatpanel.tscn") as PackedScene
	if packed == null or not packed.can_instantiate():
		check("chatpanel.tscn loads", false)
		return
	var chat: Control = packed.instantiate() as Control
	add_child(chat)
	chat.visible = true
	chat.set_process(false)
	# NOTHING ELSE WRITES THE FEED WHILE THIS RUNS. The panel polls a real
	# server if one is answering on this machine - it did, and its hundred
	# lines of world chat landed in the middle of these checks. The first poll
	# is let finish, then the timer is stopped and the gate held shut.
	var poll_timer: Timer = chat.get_node_or_null("ChatPoll") as Timer
	if poll_timer != null:
		poll_timer.stop()
	for i in 300:
		if not chat._in_flight:
			break
		await get_tree().process_frame
	chat._in_flight = true
	await get_tree().process_frame
	var now: int = int(Time.get_unix_time_from_system())
	var said := func(n: int) -> Dictionary:
		return {"kind": "chat", "by": "someone", "role": "player", "at": now, "id": 50000 + n,
			"body": "line %d - long enough to take up most of a row in the chat window, and then some" % n}
	# THE REAL PATH: a tab opened (a reset), and its first read arriving.
	chat._show_channel("world")
	var tail: Array = []
	for i in 60:
		tail.append(said.call(i))
	chat._apply_read("world", {"channel": "world", "available": true, "messages": tail,
		"removed": [], "latest_id": 50059})
	for i in 4:
		await get_tree().process_frame
	check("the first read after a tab opens is drawn once, with nothing left over",
		chat.lines_box.get_child_count() == 60 and not chat._redraw_on_next_read,
		chat.lines_box.get_child_count())
	var sc: ScrollContainer = chat.scroll
	var bar: VScrollBar = sc.get_v_scroll_bar()
	var log_box: Node = chat.lines_box
	check("sixty lines make a log taller than the window", bar.max_value > bar.page + 200,
		[bar.max_value, bar.page])
	var first_before: Node = log_box.get_child(0)
	sc.scroll_vertical = 40
	await get_tree().process_frame
	chat._add_line("world", said.call(60))
	for i in 3:
		await get_tree().process_frame
	check("a new line is added to the log, not the log rebuilt",
		log_box.get_child(0) == first_before and log_box.get_child_count() == 61, log_box.get_child_count())
	check("and a player reading further up stays where they were", sc.scroll_vertical == 40, sc.scroll_vertical)
	check("  and is told there is something new below",
		chat.new_below != null and chat.new_below.visible and chat.new_below.get_parent() == sc.get_parent()
		and chat.new_below.get_index() == sc.get_index() + 1)

	chat._apply_read("world", {"channel": "world", "available": true, "messages": [],
		"removed": [50000 + 59], "latest_id": 50060})
	for i in 3:
		await get_tree().process_frame
	check("a line taken down by staff does not pull a reader to the bottom either",
		sc.scroll_vertical == 40 and log_box.get_child_count() == 60, [sc.scroll_vertical, log_box.get_child_count()])

	sc.scroll_vertical = int(bar.max_value)
	await get_tree().process_frame
	chat._add_line("world", said.call(61))
	for i in 3:
		await get_tree().process_frame
	check("a player reading the newest lines follows the new one",
		float(sc.scroll_vertical) + bar.page >= bar.max_value - 2, [sc.scroll_vertical, bar.page, bar.max_value])
	check("  and reaching the bottom puts the \"new messages\" bar away", not chat.new_below.visible)
	sc.scroll_vertical = 40
	await get_tree().process_frame
	chat._add_line("world", said.call(9990))
	for i in 3:
		await get_tree().process_frame
	var shown_again: bool = chat.new_below.visible
	chat.new_below.pressed.emit()
	for i in 3:
		await get_tree().process_frame
	check("clicking the bar goes to the newest line and puts it away",
		shown_again and not chat.new_below.visible
		and float(sc.scroll_vertical) + bar.page >= bar.max_value - 2, [shown_again, sc.scroll_vertical])

	for i in range(62, 62 + chat.LINES_KEPT):
		chat._add_line("world", said.call(i))
	await get_tree().process_frame
	var kept: Array = chat._feeds["world"]["lines"]
	var top: RichTextLabel = log_box.get_child(0) as RichTextLabel
	check("past the cap, the oldest line leaves the screen with the feed",
		log_box.get_child_count() == kept.size() and kept.size() == chat.LINES_KEPT
		and top != null and top.get_parsed_text().contains("line %d " % int(kept[0]["id"] - 50000)),
		[log_box.get_child_count(), kept.size()])

	# SWITCHING AWAY AND BACK: the old lines stay up while the tail comes, and
	# the tail replaces them rather than landing underneath.
	chat._show_channel("guild")
	chat._show_channel("world")
	var drawn_while_waiting: int = log_box.get_child_count()
	chat._apply_read("world", {"channel": "world", "available": true,
		"messages": [said.call(900), said.call(901)], "removed": [], "latest_id": 50901})
	await get_tree().process_frame
	check("coming back to a tab shows its old lines until the tail arrives, then only the tail",
		drawn_while_waiting > 2 and log_box.get_child_count() == 2, [drawn_while_waiting, log_box.get_child_count()])

	# A READ THAT LEFT BEFORE A RESET is thrown away: its lines came after the
	# old cursor, and /r showed a reply with none of the conversation.
	var poll_body := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _poll(")
	check("a poll answer from before a feed reset is dropped, and the tail asked for",
		poll_body.contains("if generation != _feed_generation:")
		and poll_body.find("if generation != _feed_generation:") < poll_body.find("_apply_read(asked, data)"))

	var send_body := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _send(")
	check("your own line brings the log to the end, even scrolled up",
		send_body.find("_stick_to_bottom = true") != -1
		and send_body.find("_stick_to_bottom = true") < send_body.find("_poll()"))
	var add_body := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _add_line(")
	check("the open channel's new line goes through the append, never a full render",
		add_body.contains("_append_to_log()") and not add_body.contains("_render()"))
	chat.queue_free()
	print("  chat place: appended not rebuilt, reading up kept, newest followed, the cap, your own line")


func _test_whispers_reach_you() -> void:
	section("WHISPERS - said to you with chat shut, or open on another tab, and answered with /r")

	var now: int = int(Time.get_unix_time_from_system())
	var hud_script: Script = load("res://src/ui/characterhud.gd") as Script
	hud_script._forget_chat_news()
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	var rows: Control = hud.message_rows
	var chat_button: Button = hud.get_node("%chatbutton") as Button
	var news := func(whisper_id: int, who: String, body: String, at: int, guild: int) -> Dictionary:
		return {"latest_id": 0, "messages": [], "chat_news": {
			"whisper": {"id": whisper_id, "from": who, "body": body, "at": at} if whisper_id > 0 else null,
			"guild": guild, "friends": 0}}

	hud._apply_broadcast(news.call(7, "yesterday", "old news", now - 3600, 3))
	check("the first poll's old whisper and guild lines are where 'new' starts, not news",
		rows.get_child_count() == 0 and chat_button.text == "Chat", [rows.get_child_count(), chat_button.text])
	hud._apply_broadcast(news.call(8, "chatter2", "hey\n\n\nwant to trade?", now, 3))
	var toast: String = (rows.get_child(0) as Label).text if rows.get_child_count() > 0 else ""
	check("a new whisper with chat shut pops the box with who said what, on one line",
		toast == "chatter2 whispers: hey want to trade?", toast)
	check("  lights the Chat button", chat_button.text == "Chat •", chat_button.text)
	check("  and waits for the chat window, which does not exist yet",
		hud_script._whisper_waiting and hud_script._last_whisper_from == "chatter2")
	hud._mark_chat_button(false)
	hud._apply_broadcast(news.call(8, "chatter2", "hey", now, 4))
	check("a new guild line lights the Chat button too", chat_button.text == "Chat •", chat_button.text)
	check("  and the same whisper is not said twice", rows.get_child_count() == 1, rows.get_child_count())
	hud.free()

	# THROUGH A DOOR. Every area has its own HUD; a whisper from a minute ago
	# was said again in each one, and the lit Chat button went dark.
	var next_area: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	next_area._build_message_box()
	next_area._apply_broadcast(news.call(8, "chatter2", "hey", now, 4))
	check("the next area's HUD does not say the same whisper again",
		next_area.message_rows.get_child_count() == 0, next_area.message_rows.get_child_count())
	check("  and the waiting whisper still waits for the chat window",
		hud_script._whisper_waiting and hud_script._last_whisper_from == "chatter2")
	var ready_src := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _ready(")
	check("  and a new area's HUD lights the Chat button again", ready_src.contains("if _chat_dot and _chat_seen_by == Api.username:"))
	next_area.free()

	# ANOTHER ACCOUNT ON THIS MACHINE starts from nothing: the last one's ids
	# are not where "new" starts for it.
	hud_script._chat_seen_by = "someoneelse"
	hud_script._chat_seen = {"whisper": 999999, "guild": 999999, "friends": 999999}
	var other_login: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	other_login._build_message_box()
	other_login._apply_broadcast(news.call(10, "friend", "welcome back", now - 20, 0))
	check("a different account's first poll is its own, not the last player's",
		other_login.message_rows.get_child_count() == 1 and hud_script._chat_seen_by == Api.username,
		other_login.message_rows.get_child_count())
	other_login.free()

	hud_script._forget_chat_news()
	var fresh: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	fresh._build_message_box()
	fresh._apply_broadcast(news.call(9, "justnow", "you there?", now - 30, 0))
	check("a whisper from a moment before you logged in is still said",
		fresh.message_rows.get_child_count() == 1, fresh.message_rows.get_child_count())
	fresh.free()
	hud_script._forget_chat_news()

	var toggle := _func_body(_code_src("res://src/ui/characterhud.gd"), "func toggle_chat(")
	check("the chat window, when it is built, is handed the waiting whisper",
		toggle.contains("chat_panel.whisper_arrived(_last_whisper_from)")
		and toggle.contains("chat_panel.last_whisper_from = _last_whisper_from"))

	# ---- the chat window ----
	var chat: Control = (load("res://scene/ui/chat/chatpanel.tscn") as PackedScene).instantiate() as Control
	add_child(chat)
	var poll_timer: Timer = chat.get_node_or_null("ChatPoll") as Timer
	if poll_timer != null:
		poll_timer.stop()
	for i in 300:
		if not chat._in_flight:
			break
		await get_tree().process_frame
	chat._in_flight = true
	chat.visible = false
	chat.whisper_arrived("chatter2")
	check("shut, a whisper aims the Whisper tab at who sent it and lights it",
		chat._whisper_with == "chatter2" and chat._feeds["private"]["unread"] and chat._whisper_waiting)
	chat.open()
	check("  and the window opens on that conversation, not World",
		chat.visible and chat._channel == "private" and chat._whisper_with == "chatter2", chat._channel)
	chat.close()
	chat.whisper_arrived("newperson")
	chat.open()
	check("  even with another conversation in the box: the window opens on who whispered",
		chat._channel == "private" and chat._whisper_with == "newperson", chat._whisper_with)
	chat._show_channel("world")
	chat._aim_whisper("somebodyelse")
	chat.whisper_arrived("thirdperson")
	check("open on another tab, it says who whispered and how to answer",
		chat.notice.text == "thirdperson whispered you. /r to answer."
		and chat._whisper_with == "somebodyelse", [chat.notice.text, chat._whisper_with])
	chat.room_news("guild")
	chat.room_news("world")
	check("a guild line lights the Guild tab; the open tab is not marked",
		chat._feeds["guild"]["unread"] and not chat._feeds["world"]["unread"])
	chat.last_whisper_from = ""
	chat.entry.text = "/r hello"
	await chat._on_send_pressed()
	check("/r with nobody to answer says so", chat.notice.text == "Nobody has whispered you yet.", chat.notice.text)
	var send_src := _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _on_send_pressed(")
	check("  and otherwise answers whoever whispered last, in the Whisper tab",
		send_src.contains("_aim_whisper(last_whisper_from)") and send_src.contains("await _send(\"private\", answer, \"\")"))
	chat.queue_free()

	var hud_src := _func_body(_code_src("res://src/ui/characterhud.gd"), "func _apply_broadcast(")
	check("the broadcast poll's answer is where the news is read",
		hud_src.contains("_read_chat_news(data.get(\"chat_news\"))"))
	print("  whispers: the baseline, the toast, the button, the waiting window, other tabs, guild, /r, the wiring")


func _test_black_past_the_map() -> void:
	section("MAP BACKDROP - grey in the gaps of the tiles, black past the edge of the map")

	var Backdrop: Script = load("res://src/world/mapbackdrop.gd") as Script
	check("mapbackdrop.gd compiles", Backdrop != null and Backdrop.can_instantiate())
	if Backdrop == null or not Backdrop.can_instantiate():
		return
	# THE EDITOR DRAWS A SCENE OVER THE PROJECT'S CLEAR COLOUR. Set black, every
	# gap in every tile went black there too - the "graphics trip out" report.
	var project_clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	check("project.godot keeps the engine's grey, which is what the tiles were painted over",
		project_clear.is_equal_approx(Color(0.3, 0.3, 0.3, 1.0)), project_clear)
	check("  and the gaps are filled with that same grey in the game",
		Backdrop.GAPS.is_equal_approx(project_clear), Backdrop.GAPS)
	check("the game makes the screen black at runtime, for past the edge of the map",
		RenderingServer.get_default_clear_color().is_equal_approx(Backdrop.OUTSIDE)
		and Backdrop.OUTSIDE.is_equal_approx(Color.BLACK), RenderingServer.get_default_clear_color())
	check("every area that opens is given one", get_tree().scene_changed.is_connected(AreaRegistry._on_scene_changed))

	# ---- exactly the tiles, as they are drawn ----
	var area := Node2D.new()
	var layer := TileMapLayer.new()
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(16, 16)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://art/tiles/tiles4.png") as Texture2D
	atlas.texture_region_size = Vector2i(16, 16)
	atlas.create_tile(Vector2i(0, 0))
	atlas.create_tile(Vector2i(2, 0), Vector2i(2, 2))
	var source_id: int = tiles.add_source(atlas)
	layer.tile_set = tiles
	area.add_child(layer)
	for x in 3:
		layer.set_cell(Vector2i(x, 0), source_id, Vector2i(0, 0))
	layer.set_cell(Vector2i(10, 10), source_id, Vector2i(2, 0))
	var rects: Array = Backdrop.cover(area)
	check("a row of three small tiles is one rectangle, exactly under them",
		rects.has(Rect2(0, 0, 48, 16)), rects)
	check("a 32x32 tile on a 16 grid is covered where it is DRAWN - centred on its cell - not as the cell",
		rects.has(Rect2(152, 152, 32, 32)) and rects.size() == 2, rects)
	var added: Node2D = Backdrop.add_to(area)
	check("the backdrop goes under everything in the area",
		added != null and area.get_child(0) == added and not added.z_as_relative
		and added.z_index == RenderingServer.CANVAS_ITEM_Z_MIN)
	area.free()

	# ---- every real area is covered, cheaply ----
	for area_id in AreaRegistry.AREAS:
		var packed: PackedScene = load(AreaRegistry.AREAS[area_id]) as PackedScene
		if packed == null:
			continue
		var scene: Node = packed.instantiate()
		var cover: Array = Backdrop.cover(scene)
		var layers: int = scene.find_children("*", "TileMapLayer", true, false).size()
		check("%s: every tile layer is covered, in a few hundred rectangles at most" % area_id,
			(layers == 0 and cover.is_empty()) or (not cover.is_empty() and cover.size() < 600),
			[layers, cover.size()])
		scene.free()
	print("  backdrop: the editor's grey, black at runtime, exact rectangles, big tiles, under everything, every area")


func _login_screen_for_test() -> Node:
	"""The real login scene, out of the tree: _ready() never runs, so nothing
	probes a server. The @onready fields the tested code reads are filled by
	hand from the same unique names."""
	var login: Node = (load("res://scene/ui/menus/loginmenu.tscn") as PackedScene).instantiate()
	login.login_form = login.get_node_or_null("%loginform")
	login.email_form = login.get_node_or_null("%emailform")
	login.email_confirm_button = login.get_node_or_null("%emailconfirmbutton")
	login.email_status = login.get_node_or_null("%emailstatus")
	return login


func _test_signing_in_never_makes_an_account() -> void:
	section("SIGNING IN - never makes an account; creating one asks the password twice")

	var src: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var pressed: String = _func_body(src, "func _on_login_button_pressed(")
	var create: String = _func_body(src, "func _create_account(")
	# THE BUG: a mistyped name got a 401, the 401 fell through to register(),
	# and the player was in a brand new, empty account - asked for a recovery
	# email for it, with every character "gone".
	check("the sign-in button never registers a name",
		not pressed.contains("Api.register("), "a typo in your own name made a new account")
	check("  a 401 says wrong name or password, and points a new player at the sign-up link",
		pressed.contains("if res.status == 401:") and pressed.contains("Wrong name or password")
		and pressed.contains("CREATE_LINK_TEXT"))
	check("there is exactly one register() call on the screen, in the sign-up form",
		src.count("Api.register(") == 1 and create.contains("Api.register("))
	check("  and it comes after the two passwords are compared",
		create.find("if again != password:") != -1
		and create.find("if again != password:") < create.find("Api.register("))

	var login: Node = _login_screen_for_test()
	login._build_create_account()
	var form: Node = login.get_node("%loginform")
	var password: Node = login.get_node("%passwordlineedit")
	var forgot: Control = login.get_node("%recoverlinkbutton")
	var button: Button = login.get_node("%loginbutton")
	var said: Label = login.get_node("%errorlabel")
	var sign_in_text: String = button.text
	check("the second password box is built hidden, right under the password",
		login.confirm_box != null and not login.confirm_box.visible and login.confirm_box.secret
		and login.confirm_box.get_parent() == form and login.confirm_box.get_index() == password.get_index() + 1)
	check("  and the sign-up link sits under \"Forgot password?\"",
		login.create_link != null and login.create_link.get_index() == forgot.get_index() + 1
		and login.create_link.text == login.CREATE_LINK_TEXT)
	login.create_link.pressed.emit()
	check("the link turns the form into sign-up: second box, button says so, no \"Forgot password?\"",
		login._creating and login.confirm_box.visible and button.text == login.CREATE_BUTTON_TEXT
		and not forgot.visible and login.create_link.text == login.SIGN_IN_LINK_TEXT, button.text)
	login.confirm_box.text = "not the same"
	login._create_account("newplayer", "correcthorse1")
	check("  two different passwords are refused on the spot, in red",
		said.text.contains("not the same") and said.get_theme_color("font_color") == login.SAY_REFUSED
		and not login._request_in_flight, said.text)
	login.create_link.pressed.emit()
	check("and the link takes it back: one box, the scene's own button text, \"Forgot password?\"",
		not login._creating and not login.confirm_box.visible and button.text == sign_in_text
		and forgot.visible and said.text == "", [button.text, said.text])
	login._set_busy(true)
	check("  a request in flight locks the second box and the link too",
		not login.confirm_box.editable and login.create_link.disabled)
	login._set_busy(false)

	# The line a dead server left under the button goes when the server is back.
	login._say("Can't reach the server.", login.SAY_REFUSED)
	login._no_answer_line = "Can't reach the server."
	login._on_connection_changed(true)
	var cleared: bool = said.text == ""
	login._say("Wrong name or password.", login.SAY_REFUSED)
	login._on_connection_changed(true)
	check("\"can't reach the server\" is cleared when it answers again - and nothing else is",
		cleared and said.text == "Wrong name or password.", said.text)
	login.free()
	print("  sign-in: no register on a 401, one register behind two passwords, the form both ways, the stale offline line")


func _test_remember_me_means_it() -> void:
	section("REMEMBER ME - off means closing the game signs you out")

	# THE REAL FILE IS SOMEBODY'S LOGIN. This runs in the developer's own
	# user:// folder, so whatever session.cfg holds is put back afterwards.
	var had_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	var kept: String = FileAccess.get_file_as_string(Api.SESSION_PATH) if had_file else ""
	var was := [Api.token, Api.username, Api.keep_signed_in]

	Api.token = "test-token-not-real"
	Api.username = "rememberer"
	Api.keep_signed_in = false
	Api._save_session()
	var off_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	Api.keep_signed_in = true
	Api._save_session()
	var on_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	Api.keep_signed_in = false
	Api.token = ""
	Api._load_session()
	var loaded: Array = [Api.token, Api.keep_signed_in]
	Api.keep_signed_in = false
	Api._save_session()
	var cleared_file: bool = FileAccess.file_exists(Api.SESSION_PATH)
	check("with the box clear, no login is written to this computer",
		not off_file, "the next person to open the game walked into the account")
	check("with it ticked, it is", on_file)
	check("  and a login read back from disk counts as remembered", loaded == ["test-token-not-real", true], loaded)
	check("  and clearing the box later takes the file away", not cleared_file)

	if had_file:
		var f := FileAccess.open(Api.SESSION_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(kept)
			f.close()
	else:
		DirAccess.remove_absolute(Api.SESSION_PATH)
	Api.token = was[0]
	Api.username = was[1]
	Api.keep_signed_in = was[2]

	var pressed: String = _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _on_login_button_pressed(")
	check("the login screen sets it from the box before signing in or signing up",
		pressed.contains("Api.keep_signed_in = %rememberme.button_pressed")
		and pressed.find("Api.keep_signed_in") < pressed.find("_create_account(")
		and pressed.find("Api.keep_signed_in") < pressed.find("Api.login("))
	var resume: String = _func_body(_code_src("res://src/ui/menus/loginmenu.gd"), "func _check_connection_and_resume(")
	check("a remembered login goes in even while it owes a recovery address",
		not resume.contains("if Api.needs_email:"),
		"it used to stop and ask for a typed sign-in every time, so Remember me did nothing")
	print("  remember me: nothing on disk when off, on disk when on, read back as remembered, the file restored")


func _test_one_game_per_account() -> void:
	section("ONE GAME PER ACCOUNT - the game signed in over says so")

	var elsewhere := {"ok": false, "status": 401, "error": "",
		"data": {"error": "Unauthorized", "signed_in_elsewhere": true}}
	var kicked := {"ok": false, "status": 401, "error": "", "data": {"error": "Unauthorized"}}
	check("a 401 marked signed_in_elsewhere reads as another login, not a kick",
		Api.signout_notice_for(elsewhere) == Api.SIGNED_IN_ELSEWHERE_NOTICE
		and Api.signout_notice_for(kicked) == Api.SIGNED_OUT_NOTICE
		and Api.signout_notice_for({}) == Api.SIGNED_OUT_NOTICE)

	var api_src: String = _code_src("res://src/systems/api.gd")
	var probe: String = _func_body(api_src, "func probe_and_resume(")
	check("reopening the game carries a remembered login on a NEW token",
		probe.contains("post(\"/api/auth/resume\"") and probe.contains("res.data.get(\"token\"")
		and probe.contains("_save_session()"),
		"a second copy of the game found the same token and ran beside the first")
	check("  and falls back to the plain check on a server from before the route",
		probe.contains("== 404:") and probe.contains("get_json(\"/api/auth/session\""))
	var beat: String = _func_body(api_src, "func heartbeat(")
	check("the heartbeat keeps the refusal it was given, so the screen can say why",
		beat.contains("last_refusal = res"))
	var hud_src: String = _code_src("res://src/ui/characterhud.gd")
	var signout: String = _func_body(hud_src, "func _forced_signout(")
	check("the HUD signs out with that reason, from the poll or the heartbeat",
		signout.contains("signout_notice_for(") and signout.contains("Api.forget_session(notice)")
		and _func_body(hud_src, "func _on_broadcast_poll_timeout(").contains("_forced_signout(res)"))
	print("  one game per account: the notice, the resume swap, the old-server fallback, the reason carried")


func _test_email_prompt_can_wait() -> void:
	section("RECOVERY EMAIL - \"Not now\" instead of a door with only Exit")

	var login: Node = _login_screen_for_test()
	if login.email_form == null:
		check("the login scene has its email prompt", false)
		login.free()
		return
	# THROUGH THE WIRING _ready() runs, not the builder alone - a builder
	# nobody calls is a button nobody sees.
	login._wire_email_prompt()
	var later: Button = login.email_later_button
	check("the prompt has a \"Not now\" under its confirm button",
		later != null and later.get_parent() == login.email_form
		and later.get_index() == login.email_confirm_button.get_index() + 1
		and later.text == login.EMAIL_LATER_TEXT)
	login._wire_email_prompt()
	var copies: int = 0
	for child in login.email_form.get_children():
		if child is Button and (child as Button).text == login.EMAIL_LATER_TEXT:
			copies += 1
	check("  built once, however often the prompt is wired", copies == 1, copies)
	login.free()

	var src: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var pressed: String = _func_body(src, "func _on_email_later_pressed(")
	check("\"Not now\" drops the held password and carries on into the game",
		pressed.contains("_password_for_email = \"\"") and pressed.contains("_complete_login(_pending_username)"))
	print("  recovery email: Not now exists, once, in place, forgets the password, goes on in")


func _test_chat_filter() -> void:
	section("CHAT FILTER - whole words, their disguises, and never the words around them")

	var Filter: Script = load("res://src/ui/chat/chatfilter.gd") as Script
	check("the filter script loads", Filter != null)
	if Filter == null:
		return
	var masked := {
		"fuck": "f***", "Fuck!!": "F***!!", "$hit": "$***", "sh1t": "s***",
		"fuuuuuck": "f*******", "shithead": "s*******", "motherfuckers": "m************",
		"what the fuck is this": "what the f*** is this",
	}
	var wrong: Array = []
	for said in masked:
		if Filter.clean(said) != masked[said]:
			wrong.append([said, Filter.clean(said)])
	check("a listed word is masked, with its endings and its disguises", wrong.is_empty(), wrong)
	var clean_words := ["class", "assess", "Scunthorpe", "cocktail", "cocky", "as", "pass", "grape",
		"raccoon", "cumin", "spice", "Dickens", "therapist", "hello there", "sooooo good", "1v1 me"]
	var hit: Array = []
	for said in clean_words:
		if Filter.clean(said) != said:
			hit.append([said, Filter.clean(said)])
	check("and nothing that merely contains one is touched", hit.is_empty(), hit)
	var src: String = FileAccess.get_file_as_string("res://src/ui/chat/chatfilter.gd")
	check("  the list is not readable as a list in the source", not src.contains(" fuck ") and not src.contains("\"fuck"))

	var ChatPanel: Script = load("res://src/ui/chat/chatpanel.gd") as Script
	check("the chat window shows filtered text only when asked to",
		ChatPanel.shown_text("oh\nshit", true) == "oh s***" and ChatPanel.shown_text("oh\nshit", false) == "oh shit")
	check("the setting exists and is on by default", Settings.DEFAULTS.get("chat_filter") == true)
	var node_src: String = _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _node_for(")
	var picture_src: String = _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _picture_node(")
	var hud_src: String = _func_body(_code_src("res://src/ui/characterhud.gd"), "func _whisper_from(")
	check("every place a player's words are drawn goes through it: the line, a caption, the whisper pop-up",
		node_src.contains("shown_text(") and picture_src.contains("shown_text(")
		and hud_src.contains("shown_text(") and hud_src.contains("\"chat_filter\""))
	check("turning it on or off redraws what is on screen",
		_func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _on_setting_changed(").contains("_render(true)"))
	print("  chat filter: masks words and disguises, spares Scunthorpe, is a setting, reaches every drawn line")


func _test_chat_safety_menu() -> void:
	section("CHAT SAFETY - the name menu, commands, and a muted box")

	var packed: PackedScene = load("res://scene/ui/chat/chatpanel.tscn") as PackedScene
	var chat: Control = packed.instantiate() as Control
	# Out of the tree: _ready() never runs, so nothing polls a server. The
	# nodes these read are filled by hand.
	chat.entry = chat.get_node_or_null("%chatentry")
	chat.notice = chat.get_node_or_null("%chatnotice")
	for channel in chat.CHANNELS:
		chat._feeds[channel] = {"cursor": 0, "lines": [], "unread": false}
	var was := [Api.username, Api.role, Api.is_owner]
	Api.username = "me_myself"
	Api.role = "player"
	Api.is_owner = false

	var line := {"kind": "chat", "by": "rowdy", "role": "player", "id": 77, "at": 0, "body": "a line"}
	var label: RichTextLabel = chat._node_for(line) as RichTextLabel
	label.meta_clicked.emit("name")
	var menu: PopupMenu = chat.line_menu
	var items: Array = []
	if menu != null:
		for i in menu.item_count:
			if not menu.is_item_separator(i):
				items.append(menu.get_item_text(i))
	check("clicking a name opens its menu: whisper, ignore, and the five reasons to report",
		menu != null and chat._menu_line.get("by") == "rowdy"
		and items == ["Whisper", "Ignore", "Spam", "Harassment", "Hate speech", "Cheating or scams", "Something else"],
		items)
	check("  and a player is offered no mute", not items.has("Unmute"))
	var own: RichTextLabel = chat._node_for({"kind": "chat", "by": "me_myself", "role": "player",
		"id": 78, "at": 0, "body": "mine"}) as RichTextLabel
	chat._menu_line = {}
	chat.open_line_menu({"kind": "chat", "by": "me_myself", "id": 78})
	check("your own name has no menu", chat._menu_line.is_empty())
	chat.open_line_menu({"kind": "chat", "by": "themod", "role": "mod", "id": 79, "body": "x"})
	var ignore_at: int = menu.get_item_index(chat.MENU_IGNORE)
	check("staff cannot be ignored, so it is not offered", menu.is_item_disabled(ignore_at))
	Api.role = "mod"
	chat.open_line_menu(line)
	var staff_items: Array = []
	for i in menu.item_count:
		if not menu.is_item_separator(i):
			staff_items.append(menu.get_item_text(i))
	check("staff get mutes and unmute for a player's line",
		staff_items.has("Mute 10 minutes") and staff_items.has("Mute 1 day") and staff_items.has("Unmute"), staff_items)
	chat.open_line_menu({"kind": "chat", "by": "othermod", "role": "mod", "id": 80, "body": "x"})
	var peer_items: Array = []
	for i in menu.item_count:
		peer_items.append(menu.get_item_text(i))
	check("  and none for a line by their own rank", not peer_items.has("Unmute"), peer_items)
	Api.role = "player"

	chat._feeds["world"]["lines"] = [line, {"by": "Rowdy", "id": 81}, {"by": "fine", "id": 82}]
	chat._feeds["private"]["lines"] = [{"by": "rowdy", "id": 83}]
	var gone: int = chat.forget_author("ROWDY")
	check("ignoring somebody takes their lines out of every feed at once",
		gone == 3 and chat._feeds["world"]["lines"].size() == 1 and chat._feeds["private"]["lines"].is_empty(), gone)

	check("a line starting with / and a letter is a command, and never said out loud",
		chat._looks_like_command("/ignore bob") and chat._looks_like_command("/Help")
		and not chat._looks_like_command("/ ") and not chat._looks_like_command("//x")
		and not chat._looks_like_command("hi /ignore"))
	chat._run_command("/frobnicate now")
	check("an unknown command says so", chat.notice.text.contains("There is no /frobnicate command"), chat.notice.text)
	chat._run_command("/help")
	check("/help lists them", chat.notice.text.contains("/ignore") and chat.notice.text.contains("/unignore"),
		chat.notice.text)
	chat._run_command("/ignore")
	check("a command missing its name says how to use it", chat.notice.text == "Try: /ignore name", chat.notice.text)
	var send_src: String = _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _on_send_pressed(")
	check("  commands are caught before anything is sent",
		send_src.find("_looks_like_command(text)") != -1
		and send_src.find("_looks_like_command(text)") < send_src.find("await _send(_channel, text"))

	var default_hint: String = chat.entry.placeholder_text
	chat._set_muted({"until": 0, "seconds_left": 600, "reason": "spamming world"})
	check("a muted player's box says so before they type",
		chat.entry.placeholder_text == "You are muted for 10 minutes more - spamming world", chat.entry.placeholder_text)
	chat._set_muted(null)
	check("  and goes back when the mute lifts", chat.entry.placeholder_text == default_hint, chat.entry.placeholder_text)
	check("the read carries it", _func_body(_code_src("res://src/ui/chat/chatpanel.gd"), "func _apply_read(")
		.contains("_set_muted(data.get(\"muted\"))"))
	check("a 429 is said in the server's words - typing fast is not about pictures",
		chat._refusal({"status": 429, "error": "Messages are arriving faster than one every 1 seconds."})
			.begins_with("Messages are arriving"))

	# /goto: the owner's way into the Big Field, which no door reaches yet.
	var went: Array = []
	chat.go_to_area = func(area_id: String) -> bool:
		went.append(area_id)
		return true
	chat._run_command("/goto bigfield")
	check("/goto is not a command to a player", went.is_empty()
		and chat.notice.text.contains("There is no /goto command"), chat.notice.text)
	chat._run_command("/help")
	check("  and /help does not mention it", not chat.notice.text.contains("/goto"))
	Api.is_owner = true
	chat._run_command("/help")
	check("the owner's /help lists /goto", chat.notice.text.contains("/goto area"), chat.notice.text)
	chat._run_command("/goto BigField")
	check("  /goto bigfield takes the owner there, any case",
		went == ["bigfield"] and chat.notice.text == "Going to Big Field.", [went, chat.notice.text])
	chat._run_command("/goto nowhere")
	check("  a place that does not exist lists the ones that do",
		went.size() == 1 and chat.notice.text.begins_with("Try: /goto ") and chat.notice.text.contains("bigfield"),
		chat.notice.text)
	Api.is_owner = false

	Api.username = was[0]
	Api.role = was[1]
	Api.is_owner = was[2]
	label.free()
	own.free()
	chat.free()
	print("  chat safety: the menu for others, not yourself, no ignoring staff, mutes for rank, forgetting lines, commands, the muted box")


func _test_staff_reports_and_mutes() -> void:
	section("STAFF - reported lines, and chat mutes")

	var Staff: Script = load("res://src/ui/staff/staffpanel.gd") as Script
	var player := {"username": "rowdy", "role": "player", "actionable": true}
	var can: Dictionary = Staff.actions_for("mod", player)
	check("a mod can mute a player, and there is nothing to unmute yet", can["mute"] and not can["unmute"], can)
	player["mute"] = {"until": 100, "seconds_left": 3600, "reason": "spam"}
	check("  unmute appears once they are muted", Staff.actions_for("mod", player)["unmute"])
	check("  and a mod cannot mute another mod",
		not Staff.actions_for("mod", {"username": "m", "role": "mod", "actionable": true})["mute"])
	check("mute lengths read as people say them",
		[Staff.describe_minutes(600), Staff.describe_minutes(3600), Staff.describe_minutes(86400),
			Staff.describe_minutes(172800), Staff.describe_minutes(5400)]
		== ["10 minutes", "1 hour", "1 day", "2 days", "90 minutes"])
	check("mutes count on a player's record, after bans and kicks",
		Staff.describe_record({"mute": 2, "ban": 1}) == "1 ban · 2 mutes"
		and Staff.describe_record({"mute": 1}, Staff.ROW_RECORD_KINDS) == "1 mute",
		Staff.describe_record({"mute": 2, "ban": 1}))
	check("a mute says how long is left and why",
		Staff.describe_mute(player["mute"]).contains("1 hour left") and Staff.describe_mute(player["mute"]).contains("spam")
		and Staff.describe_mute(null) == "Can talk in chat")
	check("the log names mutes, unmutes and closed reports in words",
		Staff.describe_entry({"by": "m", "action": "mute", "target": "rowdy", "detail": "1 hour: spam"})
			== "m muted rowdy - 1 hour: spam"
		and Staff.KIND_LABELS.has("mute") and Staff.KIND_LABELS.has("report") and Staff.ACCOUNT_KINDS.has("mute"))

	var panel: Control = (load("res://scene/ui/staff/staffpanel.tscn") as PackedScene).instantiate() as Control
	add_child(panel)
	var role_was: String = Api.role
	Api.role = "mod"
	panel._show_detail(player)
	Api.role = role_was
	check("the Actions tab has the mute buttons and the mute on show",
		panel._mute_buttons.size() == Staff.MUTE_PRESETS.size() and not panel._mute_buttons[0].disabled
		and panel.unmute_button != null and not panel.unmute_button.disabled
		and panel.mute_label.text.contains("spam"))
	var report := {"message_id": 5, "reported": "rowdy", "reported_role": "player", "channel": "world",
		"body": "buy gold here", "said_at": 100, "reports": 2, "reporters": ["ann", "cat"],
		"reasons": {"spam": 2}, "actionable": true, "line_exists": true}
	var peer := {"message_id": 6, "reported": "othermod", "reported_role": "mod", "channel": "world",
		"body": "rude", "said_at": 100, "reports": 1, "reporters": ["ann"], "reasons": {"harassment": 1},
		"actionable": false, "line_exists": true}
	panel.apply_reports({"reports": [report, peer], "open": 2, "now": 400})
	var rows: Array = panel.reports_list.get_children()
	var buttons := func(row: Node) -> Array:
		var out: Array = []
		for b in row.find_children("*", "Button", true, false):
			out.append((b as Button).text)
		return out
	check("the Reports tab shows each reported line, and its count in the tab",
		rows.size() == 2 and panel.tabs.get_tab_title(Staff.REPORTS_TAB) == "Reports (2)",
		[rows.size(), panel.tabs.get_tab_title(Staff.REPORTS_TAB)])
	check("  a line you can act on: open the player, delete the line, mute, dismiss",
		buttons.call(rows[0]) == ["Open rowdy", "Delete line", "Mute 1 hour", "Dismiss"], buttons.call(rows[0]))
	check("  a line about your own rank: only open the player, and why",
		buttons.call(rows[1]) == ["Open othermod"], buttons.call(rows[1]))
	check("  what was said is on the row, with who reported it",
		Staff.describe_report(report, 400).contains("reported 2x (spam) by ann, cat"), Staff.describe_report(report, 400))
	panel.apply_reports({"reports": [], "open": 0, "now": 400})
	check("  and an empty tab says so", panel.reports_empty.visible and panel.tabs.get_tab_title(Staff.REPORTS_TAB) == "Reports")

	# ---- ONE CARD PER REPORTED PLAYER (day 1: the tab would flood) ----
	var line_a := {"message_id": 11, "body": "spam line 5", "channel": "world", "said_at": 300,
		"reports": 2, "line_exists": true}
	var line_b := {"message_id": 10, "body": "spam line 4", "channel": "world", "said_at": 290,
		"reports": 1, "line_exists": false}
	var bob_card := {"reported": "bob", "reported_role": "player", "actionable": true, "line_count": 6,
		"reports": 7, "people": 2, "reporters": ["ann", "cat"], "reasons": {"spam": 7},
		"first_at": 100, "last_at": 340, "lines": [line_a, line_b]}
	var mod_card := {"reported": "othermod", "reported_role": "mod", "actionable": false, "line_count": 1,
		"reports": 1, "people": 1, "reporters": ["ann"], "reasons": {"harassment": 1},
		"first_at": 100, "last_at": 100, "lines": [{"message_id": 6, "body": "rude", "channel": "world",
			"said_at": 100, "reports": 1, "line_exists": true}]}
	panel.apply_reports({"players": [bob_card, mod_card], "reports": [report, peer, report],
		"open": 7, "open_players": 2, "now": 400})
	var cards: Array = panel.reports_list.get_children()
	check("the Reports tab is a card per player, and counts players",
		cards.size() == 2 and panel.tabs.get_tab_title(Staff.REPORTS_TAB) == "Reports (2)",
		[cards.size(), panel.tabs.get_tab_title(Staff.REPORTS_TAB)])
	check("  bob's card: delete each line still in chat, then open, mute or dismiss them all",
		cards.size() == 2 and buttons.call(cards[0]) == ["Delete", "Open bob", "Mute 1 hour", "Dismiss all"],
		buttons.call(cards[0]) if cards.size() > 0 else [])
	check("  a card about your own rank only opens the player",
		cards.size() == 2 and buttons.call(cards[1]) == ["Open othermod"], buttons.call(cards[1]) if cards.size() > 1 else [])
	var card_text: Array = []
	if cards.size() > 0:
		for l in (cards[0] as Node).find_children("*", "Label", true, false):
			card_text.append((l as Label).text)
	check("  it says how many lines, people and why, and how many older lines are not shown",
		card_text.has("bob") and "\n".join(card_text).contains("6 lines · 2 people · spam ×7")
		and card_text.has("and 4 older lines") and card_text.has("\"spam line 5\""), card_text)
	check("  each line says how often, where and when, and if it is gone from chat",
		Staff.describe_card_line(line_a, 400).begins_with("×2 · world")
		and Staff.describe_card_line(line_b, 400).ends_with("gone from chat"),
		[Staff.describe_card_line(line_a, 400), Staff.describe_card_line(line_b, 400)])
	check("  and the result is said in a sentence",
		Staff.card_result_words("mute", "bob", {"reports_closed": 6}) == "Muted bob for an hour and closed 6 reported lines."
		and Staff.card_result_words("dismissed", "bob", {"lines": 1}) == "Dismissed 1 reported line about bob.",
		Staff.card_result_words("mute", "bob", {"reports_closed": 6}))
	var card_src: String = _func_body(_code_src("res://src/ui/staff/staffpanel.gd"), "func _act_on_player_reports(")
	check("  Mute is one request - the server closes the card - and Dismiss closes it by name",
		card_src.contains("Api.post(\"/api/staff/mute\"") and not card_src.contains("\"message_id\"")
		and card_src.contains("{\"username\": who, \"outcome\": what}"))
	panel.apply_reports({"reports": [report], "open": 1, "now": 400})
	check("a server from before the cards still gets its per-line rows",
		panel.reports_list.get_child_count() == 1 and buttons.call(panel.reports_list.get_child(0))[0] == "Open rowdy")

	# ---- A QUIETER LOG ----
	var runs: Array = Staff.fold_runs([
		{"id": 9, "at": 1000, "by": "boss", "action": "grant", "target": "boss", "detail": "1 x a"},
		{"id": 8, "at": 990, "by": "boss", "action": "grant", "target": "boss", "detail": "1 x b"},
		{"id": 7, "at": 900, "by": "boss", "action": "grant", "target": "boss", "detail": "1 x c"},
		{"id": 6, "at": 890, "by": "boss", "action": "ban", "target": "rowdy", "detail": "1 days: x"},
		{"id": 5, "at": 880, "by": "boss", "action": "teleport", "target": "fighter", "detail": ""},
		{"id": 4, "at": 100, "by": "boss", "action": "teleport", "target": "fighter", "detail": ""},
		{"id": 3, "at": 90, "by": "warden", "action": "teleport", "target": "fighter", "detail": ""},
	])
	var sizes: Array = []
	for run in runs:
		sizes.append(run.size())
	check("the same thing done again and again folds into one line",
		sizes == [3, 1, 1, 1, 1], sizes)
	check("  but not across a long gap, or a different person",
		runs.size() == 5 and runs[3][0]["id"] == 4 and runs[4][0]["by"] == "warden")
	panel._log = runs[0] + runs[1]
	panel._render_log()
	var folded: Button = panel.log_entries.get_child(0).find_child("fold", true, false) as Button
	check("  drawn as one line with a count, the detail left out",
		folded != null and folded.text.begins_with("▸ ") and folded.text.contains("  boss granted themselves items ×3 · from ")
		and not folded.text.contains("1 x")
		and panel.log_entries.get_child_count() == 2, folded.text if folded != null else "no fold")
	if folded != null:
		folded.pressed.emit()
	await get_tree().process_frame
	var opened: Node = panel.log_entries.get_child(panel.log_entries.get_child_count() - 2)
	var inside: Array = []
	for l in opened.find_children("*", "Label", true, false):
		inside.append((l as Label).text)
	check("  and opened with a click, every entry in it",
		inside.size() == 3 and str(inside[2]).ends_with("1 x c"), inside)
	panel._groups_ok = true
	check("a server that does not know Moderation is asked for everything instead",
		panel._group_refused({"ok": false, "status": 400}, "moderation") and not panel._groups_ok
		and not panel._group_refused({"ok": false, "status": 400}, "moderation"))
	panel._groups_ok = true
	panel.queue_free()

	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var staff_button: Button = hud.get_node("%staffbutton") as Button
	var was := [Api.role, Api.is_owner]
	Api.role = "mod"
	hud._mark_open_reports(3)
	var lit: String = staff_button.text
	hud._mark_open_reports(0)
	var dark: String = staff_button.text
	Api.role = "player"
	hud._mark_open_reports(5)
	var as_player: String = staff_button.text
	Api.role = was[0]
	Api.is_owner = was[1]
	check("the Staff button counts reported lines waiting, and only for staff",
		lit == "Staff (3)" and dark == "Staff" and as_player == "Staff", [lit, dark, as_player])
	check("  from the poll", _func_body(_code_src("res://src/ui/characterhud.gd"), "func _apply_broadcast(")
		.contains("_mark_open_reports(int(data.get(\"open_reports\", 0)))"))
	Api.role = "mod"
	hud._mark_open_reports(1, 20)
	var by_player: String = staff_button.text
	var by_player_tip: String = staff_button.tooltip_text
	Api.role = was[0]
	check("  players, not lines, from a server that counts them: one spammer is Staff (1)",
		by_player == "Staff (1)" and by_player_tip.contains("1 player reported (20 lines)"), [by_player, by_player_tip])
	check("  read from the poll's open_report_players",
		_func_body(_code_src("res://src/ui/characterhud.gd"), "func _apply_broadcast(")
		.contains("_mark_open_reports(int(data.get(\"open_report_players\", 0)), int(data.get(\"open_reports\", 0)))"))
	hud.free()
	print("  staff: mute rules and words, the Actions row, the Reports tab both ways, the Staff button count")


func _test_a_failed_load_is_not_an_empty_account() -> void:
	section("CHARACTERS - a load that did not arrive is not four empty slots")

	# THE BUG, reproduced live: the character list timed out after the login,
	# character select showed four empty slots, and Create over the warrior
	# pushed an empty backpack over the real one.
	var store_src: String = _func_body(_code_src("res://src/systems/serverstorage.gd"), "func load(")
	check("every part of the load that fails is a failed load - the list, a character, the account",
		store_src.count("return LOAD_FAILED.duplicate()") == 4 and not store_src.contains("continue\n\n\t\tslots[index]"),
		store_src.count("return LOAD_FAILED.duplicate()"))

	# A storage whose load fails, so CharacterData can be watched reading it.
	var failing := GDScript.new()
	failing.source_code = "extends SaveStorage\nvar saves := 0\nfunc load() -> Dictionary:\n\treturn {\"load_failed\": true}\nfunc save(_payload: Dictionary) -> bool:\n\tsaves += 1\n\treturn true\n"
	failing.reload()
	var was := [CharacterData.storage, CharacterData.load_failed, CharacterData.character_slots,
		CharacterData.account_data, CharacterData._save_pending, CharacterData.current_username]
	CharacterData.storage = failing.new()
	CharacterData.load_failed = false
	var loaded: bool = await CharacterData.load_data()
	var flagged: bool = CharacterData.load_failed
	CharacterData._save_pending = false
	var queued: bool = CharacterData.save_data()
	var pending_after: bool = CharacterData._save_pending
	var wrote: bool = CharacterData._write_save_now()
	var handed: int = int(CharacterData.storage.saves)
	CharacterData.storage = was[0]
	CharacterData.load_failed = was[1]
	CharacterData.character_slots = was[2]
	CharacterData.account_data = was[3]
	CharacterData._save_pending = was[4]
	CharacterData.current_username = was[5]
	check("CharacterData marks it as failed, not as a fresh account", not loaded and flagged)
	check("  and saves nothing from it - not queued, not written, nothing handed to the server",
		not queued and not pending_after and not wrote and handed == 0, [queued, pending_after, wrote, handed])
	var ld_src: String = _func_body(_code_src("res://src/systems/characterdata.gd"), "func load_for_user(")
	check("  a new load starts unflagged", ld_src.find("load_failed = false") != -1
		and ld_src.find("load_failed = false") < ld_src.find("await load_data()"))

	var login_src: String = _code_src("res://src/ui/menus/loginmenu.gd")
	var complete: String = _func_body(login_src, "func _complete_login(")
	check("the login screen does not go to character select on a failed load",
		complete.find("if CharacterData.load_failed:") != -1
		and complete.find("if CharacterData.load_failed:") < complete.find("_go_to_character_select()"))
	var pressed: String = _func_body(login_src, "func _on_login_button_pressed(")
	check("  the button tries the load again, not the login - for the same name",
		pressed.find("if _retry_load and Api.is_logged_in()") != -1
		and pressed.find("if _retry_load and Api.is_logged_in()") < pressed.find("Api.login(")
		and pressed.contains("await _complete_login(Api.username)"))
	check("  and nothing wipes the message on the way back",
		pressed.contains("if not CharacterData.load_failed:\n\t\t\t_say(\"\", SAY_WORKING)")
		and _func_body(login_src, "func _create_account(").contains("if not CharacterData.load_failed:"))

	var login: Node = _login_screen_for_test()
	login.email_form.visible = true
	login.login_form.visible = false
	var name_was: String = Api.username
	Api.username = "robert"
	login._show_load_failed()
	Api.username = name_was
	var said: Label = login.get_node("%errorlabel")
	check("it says so, on the sign-in form, with the name filled in",
		login._retry_load and login.login_form.visible and not login.email_form.visible
		and said.text.begins_with("Your characters did not load")
		and said.get_theme_color("font_color") == login.SAY_BLOCKED
		and login.get_node("%usernamelineedit").text == "robert", said.text)
	login.free()
	print("  failed load: every part counts, flagged not fresh, nothing saved, the screen stays and retries")


func _test_character_select_has_a_way_out() -> void:
	section("CHARACTER SELECT - a way back to the login screen, and a slot that says what it holds")

	var Select: Script = load("res://src/ui/menus/characterselect.gd") as Script
	check("an occupied slot says its level, not its class twice",
		Select.slot_text({"character": "warrior", "level": 12}, "warrior") == "Level 12"
		and Select.slot_text({"character": "Warrior", "level": 3}, "warrior") == "Level 3"
		and Select.slot_text({"character": "Grimnir", "level": 5}, "warrior") == "Grimnir  |  Level 5")

	var screen: Node = (load("res://scene/ui/menus/characterselect.tscn") as PackedScene).instantiate()
	screen._build_logout_row()
	var button: Button = screen.logout_button
	var grid: Node = screen.get_node("centercontainer/mainpanel/margincontainer/vboxcontainer/gridcontainer")
	check("there is a Log out button, under the four heroes",
		button != null and button.text == "Log out" and button.get_parent().get_parent() == grid.get_parent()
		and button.get_parent().get_index() == grid.get_index() + 1)
	screen._build_logout_row()
	check("  built once, and by the screen itself",
		grid.get_parent().find_children("logoutrow*", "", false, false).size() == 1
		and _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _ready(").contains("_build_logout_row()"))
	screen.free()

	var src: String = _func_body(_code_src("res://src/ui/menus/characterselect.gd"), "func _on_logout_pressed(")
	var saved: int = src.find("await CharacterData.finish_saving()")
	var cleared: int = src.find("CharacterData.clear_current_user()")
	var out: int = src.find("await Api.logout()")
	var gone: int = src.find("change_scene_to_file(LOGIN_MENU_PATH)")
	check("it saves, clears, signs out, then leaves - in that order, like the HUD's",
		saved != -1 and saved < cleared and cleared < out and out < gone, [saved, cleared, out, gone])
	check("  and not while the world is loading", src.contains("if _leaving or _entering:"))
	print("  character select: the level, Log out in place and once, and its order")


# =============================================================================
# THE MYTHIC WEAPONS - a weapon that brings its own attack
# =============================================================================
# Day 2: Ahvassa delivered a meteor, a double axe and a stick of dynamite, and
# the owner decided they are weapons - "an upgraded version of weapons because
# they have their own attack animation". Tier 6, level 22, one per class:
#
#   Meteorite (mage)    a meteor falls where you aim; one cast in ten, two
#   Double Axe (warrior) thrown to a spot, spins there, attack calls it back
#   Dynamite (tank)     a lit stick thrown where you aim, in place of the aura;
#                       one throw in ten, two sticks spread apart
#
# What can go wrong without a sound, and so is held here: an item that is not
# in the catalogue the server reads (it could never be worn), an attack that
# lands nowhere near where it was drawn, a hit that misses what is inside its
# ring or catches what is outside, an axe that never comes home or can be left
# working with nobody playing, a double cast that lands both on one spot, and a
# blast whose ground mark is placed before the blast has been moved - which
# happened: the first crater appeared under the player's spawn point.

const MYTHIC_WEAPONS := {
	"meteorite": {"class": "mage", "attack": 1, "ember": "emberstaff", "icon": 32},
	"doubleaxe": {"class": "warrior", "attack": 2, "ember": "embersword", "icon": 16},
	"dynamite": {"class": "tank", "attack": 3, "ember": "embermaul", "icon": 16},
}


func _weapon_dummy(parent: Node, at: Vector2) -> CharacterBody2D:
	# A stand-in enemy: a body on the enemies layer, in the enemies group, that
	# writes down every hit it takes.
	var script := GDScript.new()
	script.source_code = "extends CharacterBody2D\nvar taken: Array = []\n" \
		+ "func take_damage(amount: int, _element: int = 0) -> void:\n\ttaken.append(amount)\n"
	script.reload()
	var body := CharacterBody2D.new()
	body.set_script(script)
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	body.add_child(shape)
	body.add_to_group("enemies")
	parent.add_child(body)
	body.global_position = at
	return body


func _weapon_hand(parent: Node, at: Vector2) -> Node2D:
	# A stand-in warrior for the axe: one swing hits for 40 and takes a second.
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar is_dying: bool = false\nvar afk: bool = false\n" \
		+ "var caught: int = 0\nvar magic_xp: int = 0\n" \
		+ "func _calculate_melee_damage() -> int:\n\treturn 40\n" \
		+ "func attack_period() -> float:\n\treturn 1.0\n" \
		+ "func is_afk() -> bool:\n\treturn afk\n" \
		+ "func _on_axe_caught() -> void:\n\tcaught += 1\n" \
		+ "func gain_magic_xp(n: int) -> void:\n\tmagic_xp += n\n"
	script.reload()
	var hand := Node2D.new()
	hand.set_script(script)
	parent.add_child(hand)
	hand.global_position = at
	return hand


func _marks_at(parent: Node, at: Vector2) -> int:
	var found := 0
	for child in parent.get_children():
		if child.is_in_group("blastmarks") and (child as Node2D).global_position.distance_to(at) < 1.0:
			found += 1
	return found


func _test_the_mythic_weapons() -> void:
	section("MYTHIC WEAPONS - the meteor, the double axe and the dynamite")

	# --- THE ITEMS -----------------------------------------------------------
	check("the attacks are appended, never renumbered: NONE 0, METEOR 1, SPINNING_AXE 2, DYNAMITE 3",
		ItemData.WeaponAttack.NONE == 0 and ItemData.WeaponAttack.METEOR == 1
		and ItemData.WeaponAttack.SPINNING_AXE == 2 and ItemData.WeaponAttack.DYNAMITE == 3)
	var gamedata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var exported: Dictionary = {}
	for row in gamedata.get("items", []):
		exported[str(row.get("item_id", ""))] = row
	for id in MYTHIC_WEAPONS:
		var want: Dictionary = MYTHIC_WEAPONS[id]
		var item: ItemData = ItemRegistry.get_item(id)
		check("%s is in the catalogue" % id, item != null)
		if item == null:
			continue
		# Ember read from the export, not the registry: ember's icons are in
		# the private pack, and a clone without it does not load those items.
		var ember: Dictionary = exported.get(want["ember"], {})
		check("  a tier 6 %s weapon at level 22, attack %d" % [want["class"], want["attack"]],
			item.tier == 6 and item.required_level == 22 and item.type == ItemData.Type.WEAPON
			and item.equip_slot == ItemData.EquipSlot.WEAPON and item.required_classes == [want["class"]]
			and int(item.weapon_attack) == int(want["attack"]),
			[item.tier, item.required_level, item.required_classes, item.weapon_attack])
		check("  a little above ember: more damage and a bigger bonus than %s" % want["ember"],
			not ember.is_empty() and item.damage > int(ember.get("damage", 0))
			and item.bonus_damage_percent > int(ember.get("bonus_damage_percent", 0)),
			[item.damage, ember.get("damage", -1)])
		check("  its icon is drawn %dx%d, whole pixels in the slot" % [want["icon"], want["icon"]],
			item.icon != null and item.icon.get_width() == want["icon"] and item.icon.get_height() == want["icon"])
		check("  its description says what attack does", item.description.contains("Your attack"), item.description)
		var row: Dictionary = exported.get(id, {})
		check("  and the server's catalogue agrees, so it can be worn",
			int(row.get("tier", 0)) == 6 and int(row.get("required_level", 0)) == 22
			and Array(row.get("required_classes", [])) == [want["class"]]
			and str(row.get("equip_slot_name", "")) == "WEAPON", row)

	# Not sold, and no enemy's tier ladder reaches them. A mythic is a roll of
	# its own at every kill - see _test_mythic_drops().
	var sold: Array = []
	var shops := DirAccess.open("res://data/shops")
	for file in shops.get_files():
		if file.ends_with(".tres"):
			var shop: Resource = load("res://data/shops/" + file)
			for id in MYTHIC_WEAPONS:
				if Array(shop.get("stock")).has(id):
					sold.append("%s sells %s" % [file, id])
	check("no shop sells them", sold.is_empty(), sold)
	var droppers: Array = []
	var enemies_dir := DirAccess.open("res://data/enemies")
	for file in enemies_dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null:
			continue
		var odds: PackedFloat32Array = enemy.tier_odds
		var top_share: float = odds[0] if odds.size() > 0 else 0.15
		if (enemy.max_loot_tier >= 6 and top_share > 0.0) or (enemy.max_loot_tier >= 5 and enemy.tier_up_chance > 0.0):
			droppers.append(enemy.enemy_id)
	check("and no enemy's tier ladder can roll tier 6 - a mythic is its own roll", droppers.is_empty(), droppers)
	for id in ["meteor_impact", "axe_throw", "axe_catch", "dynamite_throw", "explosion"]:
		check("the %s sound has a slot waiting for its file" % id, Audio.SOUNDS.has(id))

	# Which attack each weapon gives, asked of a character built outside the tree.
	var mage: Node = (load("res://src/characters/mage.gd") as GDScript).new()
	var asked: Array = []
	for pair in [["", 0], ["emberstaff", 0], ["meteorite", 1], ["doubleaxe", 2], ["dynamite", 3]]:
		mage.equipped = {} if pair[0] == "" else {"weapon": pair[0]}
		asked.append(mage.equipped_weapon_attack() == pair[1])
	check("bare hands and ember keep the class attack; each mythic weapon brings its own",
		not asked.has(false), asked)

	var arena := Node2D.new()
	add_child(arena)
	var o := Vector2(9000, 9000)

	# --- THE METEOR ----------------------------------------------------------
	var inside: CharacterBody2D = _weapon_dummy(arena, o + Vector2(12, 0))
	var outside: CharacterBody2D = _weapon_dummy(arena, o + Vector2(45, 0))
	var caster: Node2D = _weapon_hand(arena, o + Vector2(-100, 0))
	var meteor: Meteor = (load("res://scene/projectiles/meteor.tscn") as PackedScene).instantiate()
	meteor.explosion_damage = 50
	meteor.caster = caster
	arena.add_child(meteor)
	meteor.global_position = o
	meteor.set_physics_process(false)
	# FOUR FRAMES, NOT TWO. An Area2D added in the same frame as the body it
	# should see reports nothing for its first couple of physics steps -
	# measured here, where the first area of a fresh arena saw nobody after
	# two. In the game the meteor falls for forty-four frames first.
	for i in 4:
		await get_tree().physics_frame
	meteor.advance(Meteor.FALL_SECONDS * 0.5)
	check("halfway down the meteor is in the sky, up and to one side of where it lands",
		not meteor.landed and meteor.rock.visible and meteor.rock.position.y < -20.0 and meteor.rock.position.x < 0.0,
		meteor.rock.position)
	check("  its shadow is already on the ground, and nobody has been hit",
		meteor.shadow.visible and inside.taken.is_empty())
	meteor.advance(Meteor.FALL_SECONDS * 0.6)
	check("it lands, and the enemy inside its ring takes the hit once", meteor.landed and inside.taken == [50], inside.taken)
	check("  the one outside the ring is not touched", outside.taken.is_empty(), outside.taken)
	check("  the caster is paid the stalagmite's magic XP for it", caster.magic_xp == Meteor.MAGIC_XP_ON_HIT, caster.magic_xp)
	check("  and the crater is where it landed, not where the world begins",
		_marks_at(arena, o) == 1 and get_tree().get_nodes_in_group("blastmarks").size() == 1)
	check("the stone stays in its crater, on the floor", meteor.rock.visible and meteor.rock.z_index == -1)
	meteor.advance(Meteor.COOL_SECONDS + Meteor.FADE_SECONDS + 0.05)
	check("  then cools and is gone", meteor.is_queued_for_deletion())

	mage.spawn_parent_override = arena
	mage.equipped = {"weapon": "meteorite"}
	mage.double_cast_chance = 0.0
	var aim: Vector2 = o + Vector2(0, 200)
	var one: Array = mage.call_meteor(aim)
	check("a cast with the double-cast roll missed calls one meteor, where it was aimed",
		one.size() == 1 and one[0].global_position == aim and one[0].delay == 0.0 and one[0].caster == mage)
	check("  hitting for the staff formula with the Meteorite's damage in it",
		one.size() == 1 and one[0].explosion_damage > roundi(mage.damage_per_magic * mage.get_damage_multiplier()),
		one[0].explosion_damage if one.size() == 1 else -1)
	mage.double_cast_chance = 1.0
	var two: Array = mage.call_meteor(aim)
	var apart: float = two[1].global_position.distance_to(aim) if two.size() == 2 else -1.0
	check("a double cast calls two, the second beside the first rather than on it",
		two.size() == 2 and two[0].global_position == aim
		and apart >= mage.METEOR_SPREAD_MIN - 0.01 and apart <= mage.METEOR_SPREAD_MAX + 0.01, apart)
	check("  and a moment later, so they land one after the other",
		two.size() == 2 and is_equal_approx(two[1].delay, mage.METEOR_SECOND_DELAY))
	two[1].set_physics_process(false)
	two[1].advance(mage.METEOR_SECOND_DELAY * 0.5)
	check("  the second is not even in the sky until then", not two[1].rock.visible)
	check("the mage's cast calls the meteor in place of the stalagmite when one is worn",
		_func_body(_code_src("res://src/characters/mage.gd"), "func _cast_stalagmite_drop(").contains(
			"if equipped_weapon_attack() == ItemData.WeaponAttack.METEOR:\n\t\tcall_meteor("))

	# --- THE DOUBLE AXE ------------------------------------------------------
	var row_y := o + Vector2(0, 500)
	var hand: Node2D = _weapon_hand(arena, row_y)
	var passed_by: CharacterBody2D = _weapon_dummy(arena, row_y + Vector2(60, 0))
	var at_spot: CharacterBody2D = _weapon_dummy(arena, row_y + Vector2(160, 0))
	var axe: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	axe.caster = hand
	arena.add_child(axe)
	axe.set_physics_process(false)
	axe.throw_to(hand.global_position, hand.global_position + Vector2(150, 0))
	var steps := 0
	while axe.state == SpinningAxe.State.OUT and steps < 200:
		await get_tree().physics_frame
		axe.advance(1.0 / 80.0)
		steps += 1
	check("thrown, the axe flies to the spot and starts spinning there",
		axe.state == SpinningAxe.State.SPINNING and axe.global_position.distance_to(row_y + Vector2(150, 0)) < 1.0,
		[axe.state, axe.global_position - row_y])
	check("  cutting what it passed on the way out, once, for a swing", passed_by.taken == [40], passed_by.taken)
	for i in 4:
		await get_tree().physics_frame
		axe.advance(SpinningAxe.TICK_SECONDS)
	check("spinning, it cuts what is near it every tick, for a tick's share of a swing",
		at_spot.taken == [40, 10, 10, 10, 10], at_spot.taken)
	check("  and nothing further away", passed_by.taken == [40], passed_by.taken)
	axe.recall()
	steps = 0
	while is_instance_valid(axe) and not axe.is_queued_for_deletion() and steps < 200:
		await get_tree().physics_frame
		axe.advance(1.0 / 80.0)
		steps += 1
	check("called back, it cuts what it passes on the way home too", passed_by.taken == [40, 40], passed_by.taken)
	check("  and the warrior catches it", hand.caught == 1 and (not is_instance_valid(axe) or axe.is_queued_for_deletion()))

	var far_throw: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	far_throw.caster = hand
	arena.add_child(far_throw)
	far_throw.set_physics_process(false)
	far_throw.throw_to(hand.global_position, hand.global_position + Vector2(0, 1000))
	check("a spot too far is taken as a direction: it goes as far as a throw goes",
		is_equal_approx(far_throw.target.distance_to(hand.global_position), SpinningAxe.MAX_THROW))
	far_throw.state = SpinningAxe.State.SPINNING
	hand.global_position = far_throw.global_position + Vector2(SpinningAxe.LEASH + 5.0, 0)
	far_throw.advance(0.01)
	check("walk off past the leash and it comes home on its own", far_throw.state == SpinningAxe.State.RETURNING)
	far_throw.state = SpinningAxe.State.SPINNING
	hand.global_position = far_throw.global_position + Vector2(20, 0)
	hand.afk = true
	far_throw.advance(0.01)
	check("go away from the keyboard and it comes home - no axe left grinding a spawn",
		far_throw.state == SpinningAxe.State.RETURNING)
	hand.afk = false
	hand.is_dying = true
	far_throw.advance(0.01)
	check("die and it is simply gone", far_throw.is_queued_for_deletion())
	hand.is_dying = false

	var wall := StaticBody2D.new()
	wall.collision_layer = 2
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(8, 200)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	arena.add_child(wall)
	wall.global_position = hand.global_position + Vector2(80, 0)
	var stopped: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	stopped.caster = hand
	arena.add_child(stopped)
	stopped.set_physics_process(false)
	stopped.throw_to(hand.global_position, hand.global_position + Vector2(150, 0))
	steps = 0
	while stopped.state == SpinningAxe.State.OUT and steps < 200:
		await get_tree().physics_frame
		stopped.advance(1.0 / 80.0)
		steps += 1
	check("thrown at a wall, it stops at the wall and spins there rather than passing through",
		stopped.state == SpinningAxe.State.SPINNING and stopped.global_position.x < wall.global_position.x,
		stopped.global_position - hand.global_position)
	stopped.queue_free()

	var warrior: Node = (load("res://src/characters/warrior.gd") as GDScript).new()
	warrior._set_stat_curve()
	warrior.spawn_parent_override = arena
	warrior.equipped = {"weapon": "doubleaxe"}
	warrior.position = o + Vector2(0, 800)
	var thrown: SpinningAxe = warrior.throw_axe(warrior.position + Vector2(100, 0))
	check("the warrior throws one axe, at the spot", thrown != null and warrior.axe_is_out()
		and thrown.caster == warrior and thrown.target == warrior.position + Vector2(100, 0))
	check("  and only one: asking again while it is out hands back the same axe",
		warrior.throw_axe(warrior.position + Vector2(0, 100)) == thrown)
	warrior.attack_action()
	check("attack while it is out calls it back", thrown.state == SpinningAxe.State.RETURNING)
	var attack_src: String = _func_body(_code_src("res://src/characters/warrior.gd"), "func attack_action(")
	check("  and the swing that throws it carries no hitbox and no slash wave",
		attack_src.contains("_swing_hitbox = null") and attack_src.contains("_wave_spawned_this_swing = true")
		and attack_src.contains("throw_axe("))
	warrior.equipped = {}
	warrior.refresh_gear_stats()
	check("taking the axe off while it is out takes it out of the world",
		not warrior.axe_is_out() and thrown.is_queued_for_deletion())

	# --- THE DYNAMITE --------------------------------------------------------
	var land := o + Vector2(0, 1100)
	var near_blast: CharacterBody2D = _weapon_dummy(arena, land + Vector2(15, 0))
	var past_blast: CharacterBody2D = _weapon_dummy(arena, land + Vector2(50, 0))
	var stick: Dynamite = (load("res://scene/projectiles/dynamite.tscn") as PackedScene).instantiate()
	stick.explosion_damage = 30
	arena.add_child(stick)
	stick.set_physics_process(false)
	stick.throw_from(land + Vector2(-120, 0), land)
	stick.advance(Dynamite.FLIGHT_SECONDS * 0.5)
	check("halfway there the stick is in the air above its shadow, partway along",
		stick.state == Dynamite.State.FLYING and stick.stick.position.y < -15.0
		and stick.global_position.x > land.x - 120.0 and stick.global_position.x < land.x,
		[stick.stick.position, stick.global_position - land])
	stick.advance(Dynamite.FLIGHT_SECONDS * 0.5 + 0.01)
	check("it lands where it was thrown and lies there, fuse lit",
		stick.state == Dynamite.State.FUSE and stick.global_position == land and stick.stick.position.y > -5.0)
	for i in 4:
		await get_tree().physics_frame
	stick.advance(0.5)
	check("  the fuse burns - half a second on, nothing has been hit yet", not stick.exploded and near_blast.taken.is_empty())
	stick.advance(Dynamite.FUSE_SECONDS)
	check("then it goes off: the enemy inside the blast is hit once", stick.exploded and near_blast.taken == [30], near_blast.taken)
	check("  the one outside it is not", past_blast.taken.is_empty(), past_blast.taken)
	check("  and the scorch is where it went off", _marks_at(arena, land) == 1)

	var tank: Node = (load("res://src/characters/tank.gd") as GDScript).new()
	tank._set_stat_curve()
	tank.level = 22
	tank.spawn_parent_override = arena
	tank.equipped = {"weapon": "dynamite"}
	tank.mana = 100
	tank.position = o + Vector2(0, 1400)
	tank.double_cast_chance = 0.0
	var sticks: Array = tank.throw_dynamite(tank.position + Vector2(1000, 0))
	check("the tank throws one stick, as far as a throw goes, for its mana",
		sticks.size() == 1 and sticks[0].landing_spot() == tank.position + Vector2(tank.DYNAMITE_MAX_THROW, 0)
		and tank.mana == 100 - tank.dynamite_mana_cost,
		[sticks.size(), tank.mana])
	check("  worth the four aura ticks it replaces, with the Dynamite's damage in them",
		sticks.size() == 1 and sticks[0].explosion_damage >= roundi(tank.aura_damage * tank.get_damage_multiplier() * 4.0),
		sticks[0].explosion_damage if sticks.size() == 1 else -1)
	check("  and not again until the cooldown is over",
		tank.throw_dynamite(tank.position + Vector2(50, 0)).is_empty() and tank.mana == 100 - tank.dynamite_mana_cost)
	tank._dynamite_cooldown_left = 0.0
	tank.double_cast_chance = 1.0
	var pair: Array = tank.throw_dynamite(tank.position + Vector2(100, 0))
	var spots: Array = pair.map(func(d): return d.landing_spot() - tank.position)
	check("a double throw is two sticks, either side of the aim, across the throw",
		pair.size() == 2 and spots.has(Vector2(100, tank.DYNAMITE_SPREAD)) and spots.has(Vector2(100, -tank.DYNAMITE_SPREAD)),
		spots)
	check("  for one throw's mana, the second a moment behind the first",
		tank.mana == 100 - 2 * tank.dynamite_mana_cost and pair.size() == 2
		and pair[0].delay == 0.0 and is_equal_approx(pair[1].delay, tank.DYNAMITE_SECOND_DELAY))
	tank.aura_active = true
	tank.refresh_gear_stats()
	check("dynamite on while the aura burns puts the aura out", not tank.aura_active)
	check("attack throws dynamite instead of toggling the aura when it is worn",
		_func_body(_code_src("res://src/characters/tank.gd"), "func attack_action(").contains(
			"if equipped_weapon_attack() == ItemData.WeaponAttack.DYNAMITE:\n\t\tthrow_dynamite("))
	check("  and the cooldown runs down in the tank's own loop",
		_func_body(_code_src("res://src/characters/tank.gd"), "func _physics_process(").contains("_dynamite_cooldown_left"))

	arena.queue_free()
	await get_tree().process_frame
	mage.free()
	warrior.free()
	tank.free()
	print("  mythic weapons: three items, the meteor, the axe out and home, the dynamite, double casts")


# =============================================================================
# THE OWNER'S ITEM MENU - every item, one click, and the level to wear it
# =============================================================================
# Day 2: "i need these items as hot keys so i can test - can you create a menu
# in hud that allows me to select and spawn items registered in the game that
# only owner can use". And, because the weapons it was for need level 22, the
# owner's own level, set on the server. Driven here through the panel's own
# doors: post_request, adopt_bag, equip_request and apply_level are Callables
# the suite swaps for stubs that write down what they were asked.

func _menu_item(id: String, type: int, slot: int = 0, stack: int = 1) -> ItemData:
	var item := ItemData.new()
	item.item_id = id
	item.display_name = id
	item.type = type as ItemData.Type
	item.equip_slot = slot as ItemData.EquipSlot
	item.stackable = stack > 1
	item.max_stack = stack
	return item


func _test_mythic_drops() -> void:
	section("MYTHIC DROPS - any enemy, the tougher the better, and a moment when one lands")

	# --- THE ODDS --------------------------------------------------------------
	# Day 2, the owner: regular mobs and bosses both drop the mythic weapons,
	# "mixed rarity but it should be super rewarding getting 1". The server
	# rolls (gamedata.roll_mythic); the game authors the odds and exports them.
	check("the mythic tier is 6", GameConstants.MYTHIC_TIER == 6
		and GameConstants.rarity_name(GameConstants.MYTHIC_TIER) == "Mythic")
	var boss_table: Dictionary = GameConstants.MYTHIC_ODDS_BOSS_BY_TIER
	var table: Dictionary = GameConstants.MYTHIC_ODDS_BY_TIER
	check("every boss rate beats every regular rate",
		boss_table.values().max() < table.values().min(), [boss_table, table])
	var tiers: Array = table.keys()
	tiers.sort()
	var ordered: bool = tiers == [1, 2, 3, 4, 5]
	for i in range(1, tiers.size()):
		ordered = ordered and int(table[tiers[i]]) < int(table[tiers[i - 1]])
	check("every band has a rate, and a higher band always has the better odds", ordered, table)
	check("a mythic bag stays longer than any other, and inside the server's 600 seconds",
		GameConstants.MYTHIC_BAG_DESPAWN_SECONDS > GameConstants.LOOT_BAG_DESPAWN_SECONDS
		and GameConstants.MYTHIC_BAG_DESPAWN_SECONDS < 600.0, GameConstants.MYTHIC_BAG_DESPAWN_SECONDS)

	var rule := EnemyData.new()
	rule.max_loot_tier = 3
	var normal_odds: int = rule.mythic_odds()
	rule.slots_are_gear = true
	rule.max_loot_tier = 5
	var boss_odds: int = rule.mythic_odds()
	rule.mythic_odds_override = 150
	var override_odds: int = rule.mythic_odds()
	rule.grants_rewards = false
	var unpaid_odds: int = rule.mythic_odds()
	var beyond := EnemyData.new()
	beyond.max_loot_tier = 9
	check("EnemyData.mythic_odds(): the regular table by tier", normal_odds == int(table[3]), normal_odds)
	check("  the boss table for a boss", boss_odds == int(boss_table[5]), boss_odds)
	check("  the override over either", override_odds == 150, override_odds)
	check("  never for an enemy that pays nothing", unpaid_odds == 0, unpaid_odds)
	check("  and never for a tier the tables do not name", beyond.mythic_odds() == 0, beyond.mythic_odds())

	# The authored enemies, against the export the server reads.
	var gamedata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gamedata.json"))
	var rows: Dictionary = {}
	for row in gamedata.get("enemies", []):
		rows[str(row.get("enemy_id", ""))] = row
	var stale: Array = []
	var unpaid: Array = []
	var best_id: String = ""
	var best: int = 0
	var enemies_dir := DirAccess.open("res://data/enemies")
	for file in enemies_dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var enemy: EnemyData = load("res://data/enemies/" + file) as EnemyData
		if enemy == null:
			continue
		var odds: int = enemy.mythic_odds()
		if int(rows.get(enemy.enemy_id, {}).get("mythic_odds", -1)) != odds:
			stale.append("%s: %d here, %s exported" % [enemy.enemy_id, odds, rows.get(enemy.enemy_id, {}).get("mythic_odds", "none")])
		if enemy.grants_rewards and odds <= 0:
			unpaid.append(enemy.enemy_id)
		if odds > 0 and (best == 0 or odds < best):
			best = odds
			best_id = enemy.enemy_id
	check("the export the server reads has every enemy's mythic odds, and they are current", stale.is_empty(), stale)
	check("every enemy that pays rewards can drop one", unpaid.is_empty(), unpaid)
	check("the Crowned is the best hunt in the game", best_id == "boss", [best_id, best])
	check("and the export names the tier they pay from",
		int(gamedata.get("constants", {}).get("mythic_tier", 0)) == GameConstants.MYTHIC_TIER)

	# --- THE BAG -------------------------------------------------------------
	var bag_scene: PackedScene = load("res://scene/interactables/lootbag.tscn") as PackedScene
	var plain: Node = bag_scene.instantiate()
	add_child(plain)
	var bag: Node = bag_scene.instantiate()
	add_child(bag)
	await get_tree().process_frame
	check("an ordinary bag stays %d seconds" % int(GameConstants.LOOT_BAG_DESPAWN_SECONDS),
		is_equal_approx(plain.despawn_timer.wait_time, GameConstants.LOOT_BAG_DESPAWN_SECONDS)
		and not plain.is_mythic(), plain.despawn_timer.wait_time)
	plain.free()
	bag.set_contents([{"item_id": "meteorite", "quantity": 1}])
	bag.despawn_timer.paused = true
	bag.set_mythic(true)
	check("a mythic bag stays five minutes", is_equal_approx(bag.despawn_timer.wait_time,
		GameConstants.MYTHIC_BAG_DESPAWN_SECONDS) and not bag.despawn_timer.is_stopped(), bag.despawn_timer.wait_time)
	check("  and a pause the open panel put on it holds", bag.despawn_timer.paused)
	check("  it glows mythic red", bag.glow_tier() == GameConstants.MYTHIC_TIER, bag.glow_tier())
	var pillar: Sprite2D = bag.get_node_or_null("rareglow/pillar") as Sprite2D
	check("  with the pillar raised high above the sack", pillar != null and pillar.scale == bag.MYTHIC_GLOW_SCALE
		and pillar.position.y < -bag.GLOW_PILLAR_HEIGHT, ("%s at %s" % [pillar.scale, pillar.position]) if pillar != null else "no pillar")
	check("  and a burst of sparks as it lands", bag.get_node_or_null("mythicsparks") is CPUParticles2D)
	bag.set_contents([null])
	check("taking the mythic out ends the show", not bag.is_mythic() and bag.glow_tier() == 0)
	bag.free()

	# --- THE FINDER'S MOMENT -------------------------------------------------
	# Combat._spawn_loot_bag() with the answer a mythic kill gets. A HUD and a
	# player stand in as stubs that remember what they were asked.
	for old in get_tree().get_nodes_in_group(&"lootbags"):
		old.free()
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node2D\nvar banners: Array = []\nvar shakes: Array = []\n" \
		+ "func show_mythic_banner(title: String, line: String, flash: bool = false) -> void:\n" \
		+ "\tbanners.append([title, line, flash])\n" \
		+ "func shake_camera(strength: float, seconds: float) -> void:\n" \
		+ "\tshakes.append([strength, seconds])\n"
	stub_script.reload()
	var hud_stub := Node2D.new()
	hud_stub.set_script(stub_script)
	add_child(hud_stub)
	hud_stub.add_to_group("hud")
	var finder := Node2D.new()
	finder.set_script(stub_script)
	add_child(finder)
	var hud_first: bool = get_tree().get_first_node_in_group("hud") == hud_stub
	check("(the stub is the HUD Combat finds)", hud_first)
	Combat._spawn_loot_bag({"bag_id": "mythictest", "mythic": "meteorite",
		"contents": [{"position": 0, "item_id": "meteorite", "quantity": 1}]}, finder, Vector2(40, 40))
	var spawned: Node = null
	for node in get_tree().get_nodes_in_group(&"lootbags"):
		if node.has_method("get_bag_id") and node.get_bag_id() == "mythictest":
			spawned = node
	check("a mythic kill's bag is a mythic bag", spawned != null and spawned.is_mythic())
	check("the finder gets the MYTHIC DROP banner, naming the piece, with the flash",
		hud_first and hud_stub.banners == [["MYTHIC DROP!", "Meteorite", true]], hud_stub.banners)
	check("  and a camera shake harder than any weapon's",
		finder.shakes == [[Combat.MYTHIC_SHAKE_STRENGTH, Combat.MYTHIC_SHAKE_SECONDS]]
		and Combat.MYTHIC_SHAKE_STRENGTH > 3.0, finder.shakes)
	var combat_src: String = FileAccess.get_file_as_string("res://src/systems/combat.gd")
	check("  and the mythic_drop sound", _first_code_index(combat_src, "Audio.play(\"mythic_drop\")", 0) != -1
		and Audio.SOUNDS.has("mythic_drop"))
	if spawned != null:
		spawned.free()
	Combat._spawn_loot_bag({"bag_id": "plaintest",
		"contents": [{"position": 0, "item_id": "meteorite", "quantity": 1}]}, finder, Vector2(40, 40))
	var ordinary: Node = null
	for node in get_tree().get_nodes_in_group(&"lootbags"):
		if node.has_method("get_bag_id") and node.get_bag_id() == "plaintest":
			ordinary = node
	check("a kill the server did not name a mythic gets no show",
		ordinary != null and not ordinary.is_mythic() and hud_stub.banners.size() == 1, hud_stub.banners)
	if ordinary != null:
		ordinary.free()
	hud_stub.free()
	finder.free()

	# --- EVERYONE ELSE -------------------------------------------------------
	var was_name: String = Api.username
	Api.username = "watcher"
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	var red: Color = GameConstants.rarity_colour(GameConstants.MYTHIC_TIER)
	var said: String = "Tunacan found the Meteorite on The Crowned!"
	hud._read_broadcast_messages([{"kind": "mythic", "body": said, "by": "Tunacan", "at": 1700000000}], true)
	var banner: Control = hud.mythic_banner
	check("a find by somebody else puts the red banner up for everyone online",
		banner != null and (banner.get_node("rows/title") as Label).text == "MYTHIC FOUND"
		and (banner.get_node("rows/line") as Label).text == said, banner)
	check("  with no flash - that is the finder's", banner != null and banner.get_node_or_null("flash") == null)
	var last: Variant = hud._unlogged_lines.back() if not hud._unlogged_lines.is_empty() else null
	check("  and writes it into chat in the mythic red",
		last is Dictionary and last["text"] == said and last["color"] == red and int(last["at"]) == 1700000000, last)
	check("  without a second box popping under the banner", hud.message_rows.get_child_count() == 0,
		hud.message_rows.get_child_count())
	banner.free()
	hud.mythic_banner = null
	hud._read_broadcast_messages([{"kind": "mythic", "body": "watcher found the Dynamite on a Light Slime!",
		"by": "watcher", "at": 1700000001}], true)
	check("your own find is only written into chat - your game already celebrated",
		hud.mythic_banner == null and hud._unlogged_lines.back()["color"] == red)
	hud._read_broadcast_messages([{"kind": "mythic", "body": said, "by": "Tunacan", "at": 1600000000}], false)
	check("an old find a first poll catches up on is not announced", hud.mythic_banner == null)
	hud._read_broadcast_messages([{"kind": "system", "body": "Server restarting soon.", "by": "boss", "at": 1700000002}], true)
	check("an ordinary notice is still gold, with no banner",
		hud.mythic_banner == null and hud._unlogged_lines.back()["color"] == Color(1.0, 0.82, 0.42))
	hud.free()
	Api.username = was_name


func _test_the_item_menu() -> void:
	section("THE ITEM MENU - the owner's whole catalogue, and a level to test it at")

	# BY PATH, NOT BY class_name. A class_name is known to a headless run only
	# after the editor has rescanned (see "A brand-new class_name is invisible
	# until the editor rescans" in CLAUDE.md), and this file naming ItemSpawner
	# made the whole suite fail to compile on a checkout the editor had not
	# opened since the menu arrived. A preload resolves by path either way.
	const Spawner := preload("res://src/ui/owner/itemspawner.gd")

	var packed: PackedScene = load("res://scene/ui/owner/itemspawner.tscn") as PackedScene
	check("itemspawner.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var was_owner: bool = Api.is_owner
	var was_role: String = Api.role
	Api.is_owner = true
	Api.role = "owner"
	var menu: Control = packed.instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	check("it is a window of its own", menu.get("_window") != null)

	# --- WHERE EVERYTHING IS LISTED ---
	var T := ItemData.Type
	var S := ItemData.EquipSlot
	var kinds: Array = [
		[_menu_item("w", T.WEAPON, S.WEAPON), "Weapons"],
		[_menu_item("h", T.ARMOR, S.HELM), "Armour"],
		[_menu_item("s", T.ARMOR, S.SHIELD), "Armour"],
		[_menu_item("a", T.ARMOR, S.AMULET), "Jewellery"],
		[_menu_item("r", T.ARMOR, S.RING), "Jewellery"],
		[_menu_item("p", T.CONSUMABLE, S.NONE, 99), "Potions and food"],
		[_menu_item("pet", T.PET), "Pets"],
		[_menu_item("fish", T.FISH), "Fishing"],
		[_menu_item("ironfishingrod", T.MATERIAL), "Fishing"],
		[_menu_item("fishingworm", T.MATERIAL, S.NONE, 99), "Fishing"],
		[_menu_item("coin", T.CURRENCY), "Currency"],
		[_menu_item("trophy", T.ARMOR, S.NONE), "Other"],
	]
	var wrong: Array = []
	for pair in kinds:
		if Spawner.category_of(pair[0]) != pair[1]:
			wrong.append("%s -> %s" % [pair[0].item_id, Spawner.category_of(pair[0])])
	check("every item is listed under what it is", wrong.is_empty(), wrong)
	check("  and every kind it can be is one of the menu's",
		kinds.all(func(pair): return Spawner.CATEGORIES.has(pair[1])))

	menu.search.text = ""
	menu.category.select(0)
	menu.refresh()
	var everything: int = ItemRegistry.get_all_items().size()
	check("All lists every item the registry loaded", menu.listed().size() == everything
		and menu.grid.get_child_count() == everything, [menu.listed().size(), everything])
	menu.search.text = "METEOR"
	menu.refresh()
	var found: Array = menu.listed().map(func(i): return i.item_id)
	check("the search reads names and ids, any case", found.has("meteorite"), found)
	menu.search.text = "double axe"
	menu.refresh()
	found = menu.listed().map(func(i): return i.item_id)
	check("  and every word of it", found == ["doubleaxe"], found)
	menu.search.text = "doubleaxe"
	menu.refresh()
	found = menu.listed().map(func(i): return i.item_id)
	check("  and the id the server and the logs call it by", found == ["doubleaxe"], found)
	menu.search.text = ""
	menu.category.select(Spawner.CATEGORIES.find("Weapons"))
	menu.refresh()
	check("a kind lists that kind and nothing else",
		not menu.listed().is_empty() and menu.listed().all(func(i): return i.type == ItemData.Type.WEAPON))
	var tiers: Array = menu.listed().map(func(i): return i.tier)
	var sorted_tiers: Array = tiers.duplicate()
	sorted_tiers.sort()
	check("  cheapest first, the mythic weapons last", tiers == sorted_tiers, tiers)
	var axe_cell: Button = menu.grid.get_node_or_null("doubleaxe") as Button
	check("a cell shows the item's picture and says what it is",
		axe_cell != null and axe_cell.icon != null and axe_cell.tooltip_text.contains("Double Axe")
		and axe_cell.tooltip_text.contains("level 22") and axe_cell.tooltip_text.contains("id: doubleaxe"),
		axe_cell.tooltip_text if axe_cell != null else "")
	check("one click spawns it", axe_cell != null and axe_cell.pressed.get_connections().size() > 0)

	check("a sword comes one at a time, however many are asked for",
		Spawner.quantity_for(_menu_item("w", T.WEAPON, S.WEAPON), 40) == 1)
	check("  and potions up to their stack, never past it",
		Spawner.quantity_for(_menu_item("p", T.CONSUMABLE, S.NONE, 99), 40) == 40
		and Spawner.quantity_for(_menu_item("p", T.CONSUMABLE, S.NONE, 99), 500) == 99)

	# --- SPAWNING, through the stubs ---
	var asked: Array = []
	var adopted: Array = []
	var equipped: Array = []
	var levels: Array = []
	var answer: Array = [{"ok": true, "data": {"inventory": [null, {"item_id": "doubleaxe", "quantity": 1}],
		"carry_positions": [1]}}]
	menu.post_request = func(path: String, body: Dictionary) -> Dictionary:
		asked.append([path, body])
		await get_tree().process_frame
		return answer[0]
	menu.adopt_bag = func(slot_index: int, bag_cells: Array) -> void:
		adopted.append([slot_index, bag_cells])
	menu.equip_request = func(id: String, cell: int) -> bool:
		equipped.append([id, cell])
		return true
	menu.apply_level = func(data: Dictionary) -> void:
		levels.append(data)

	menu.quantity.value = 5
	menu.wear_toggle.button_pressed = true
	await menu.spawn("doubleaxe")
	check("a click asks the server for it: the grant route, this character, one axe",
		asked.size() == 1 and asked[0][0] == "/api/staff/grant" and asked[0][1].get("item_id") == "doubleaxe"
		and asked[0][1].get("quantity") == 1 and asked[0][1].get("slot") == CharacterData.active_character_index,
		asked)
	check("  the bag the server sends back is adopted", adopted.size() == 1 and adopted[0][1].size() == 2)
	check("  and the axe is put on from the cell it landed in", equipped == [["doubleaxe", 1]], equipped)
	check("  and the menu says so", menu.status.text == "Added Double Axe and put it on.", menu.status.text)

	menu.wear_toggle.button_pressed = false
	await menu.spawn("doubleaxe")
	check("with \"put gear on\" off, it only goes in the bag",
		equipped.size() == 1 and menu.status.text == "Added 1 × Double Axe to your bag.", menu.status.text)
	# A potion of the suite's own, registered for the moment: the real ones'
	# pictures are in the private art pack, and a clone without it does not
	# load them.
	var potion: ItemData = _menu_item("menutest_potion", T.CONSUMABLE, S.NONE, 99)
	ItemRegistry._items[potion.item_id] = potion
	menu.wear_toggle.button_pressed = true
	await menu.spawn("menutest_potion")
	ItemRegistry._items.erase(potion.item_id)
	check("something that is not gear is never put on, and comes as many as asked",
		equipped.size() == 1 and asked[-1][1].get("item_id") == "menutest_potion"
		and asked[-1][1].get("quantity") == 5, [equipped, asked[-1]])

	answer[0] = {"ok": false, "status": 409, "error": "Your backpack is full."}
	var adopted_before: int = adopted.size()
	await menu.spawn("meteorite")
	check("a refusal is said in the server's words, and nothing is adopted",
		menu.status.text == "Your backpack is full." and adopted.size() == adopted_before, menu.status.text)

	Api.is_owner = false
	var asked_before: int = asked.size()
	await menu.spawn("meteorite")
	check("anyone but the owner is told it is the owner's, and nothing is asked",
		asked.size() == asked_before and menu.status.text.contains("owner"), menu.status.text)
	await menu.set_level(22)
	check("  the level too", asked.size() == asked_before and levels.is_empty())
	Api.is_owner = true

	answer[0] = {"ok": true, "data": {"level": 22, "was": 3, "xp": 0, "xp_to_next": 99,
		"hp": 432, "mana": 390, "stamina": 185}}
	await menu.set_level(22)
	check("Set level asks the owner's level route for this character",
		asked[-1][0] == "/api/staff/level" and asked[-1][1].get("level") == 22
		and asked[-1][1].get("slot") == CharacterData.active_character_index, asked[-1])
	check("  and the character takes the server's answer", levels.size() == 1 and levels[0].get("level") == 22)
	check("  and the box shows the level it is now", int(menu.level_box.value) == 22)

	# --- THE CHARACTER'S HALF ---
	var warrior: Node = (load("res://scene/characters/warrior.tscn") as PackedScene).instantiate()
	warrior._set_stat_curve()
	warrior.equipped = {}
	warrior.level = 3
	warrior.hp = 5
	warrior.apply_server_level({"level": 22, "xp": 0, "xp_to_next": 777, "hp": 9999, "mana": 3, "stamina": 40})
	check("a character copies a level the server set: level, XP and the next step",
		warrior.level == 22 and warrior.xp == 0 and warrior.xp_next == 777)
	check("  the maxima follow the level, and the pools are the server's, never over the maxima",
		warrior.max_hp == PlayerStats.max_for(warrior.hp_base, warrior.hp_per_lvl, 22)
		and warrior.hp == warrior.max_hp and warrior.mana == 3 and warrior.stamina == 40, [warrior.hp, warrior.max_hp])
	warrior.free()

	var said: Array = []
	var listener := func(r): said.append(r)
	CharacterData.carry_adopted.connect(listener)
	var saved_slots = CharacterData.character_slots.duplicate(true)
	var saved_index: int = CharacterData.active_character_index
	CharacterData.character_slots = [{"character": "warrior", "inventory": []}, null, null, null]
	CharacterData.active_character_index = 0
	var cells: Array = [{"item_id": "doubleaxe", "quantity": 1}, null]
	var landed: bool = CharacterData.adopt_granted_bag(0, cells, null)
	var bag = CharacterData.character_slots[0].get("inventory", [])
	CharacterData.carry_adopted.disconnect(listener)
	CharacterData.character_slots = saved_slots
	CharacterData.active_character_index = saved_index
	check("the granted bag lands on the character", landed and bag is Array and bag.size() == 2
		and bag[0] is Dictionary and bag[0].get("item_id") == "doubleaxe")
	check("  without \"your backpack was updated by the server\" - you asked", said.is_empty(), said)

	# --- THE DOOR, on the real HUD built out of the tree ---
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var row: Control = hud.get_node_or_null("%staffrow") as Control
	Api.role = "mod"
	Api.is_owner = false
	hud._add_owner_button()
	check("a mod has no Items button", row != null and not row.has_node("itemsbutton"))
	Api.role = "owner"
	Api.is_owner = true
	hud._add_owner_button()
	var items_button: Button = row.get_node_or_null("itemsbutton") as Button if row != null else null
	check("the owner has one on the staff row, and it opens the menu",
		items_button != null and items_button.pressed.is_connected(Callable(hud, "toggle_item_spawner")))
	hud.item_spawner = menu
	menu.visible = true
	check("Escape counts the menu as open", hud.is_panel_open())
	hud.hide_panel()
	check("  and closes it", not menu.visible)
	hud.item_spawner = null
	hud.free()

	menu.queue_free()
	Api.is_owner = was_owner
	Api.role = was_role
	await get_tree().process_frame
	print("  item menu: every item, searchable, spawned and worn; the owner's level; owner only")
