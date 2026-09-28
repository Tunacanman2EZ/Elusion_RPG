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
var skipped: int = 0
var skips: PackedStringArray = []
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
	_test_login_states_are_distinct()
	_test_no_import_cache_references()
	_test_no_unused_parameters()
	_test_floor_coverage()
	_test_frame_budget()


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
		for name in LICENCE_FILENAMES:
			if FileAccess.file_exists(folder.path_join(name)):
				found = name
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
	# ASSIGNED, OR HONESTLY EMPTY, BUT NEVER HALF
	# =========================================================================
	# Nobody ships a game and fails to notice it makes no noise at all. What
	# ships unnoticed is twenty-six sounds assigned and five forgotten, because
	# the boot line still prints a number and nothing reads it.
	#
	# So zero is a SKIP - the game is deliberately silent today and saying so
	# twice does not make it truer - all is a PASS, and the middle FAILS and
	# names what is missing. docs/audio.md is the list to work from.
	if filled == 0:
		skipped += 1
		skips.append("the sound registry is filled in   (0 of %d assigned; the "
			% sounds.size() + "game is deliberately silent - see docs/audio.md)")
		_say("  skip  the sound registry is filled in   (0 of %d assigned, the game is silent)"
			% sounds.size())
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

	# The honest limit the page inherits from the server's list.
	check("the page still names the backpack ledger as client-declared",
		doc.contains("backpack ledger is still client-declared"),
		"an open gap dropped from the page reads as a gap that was closed")

	check("and it tells people where to report without publishing an inbox",
		doc.contains("Report a vulnerability") and not doc.contains("@gmail"),
		"a documented security address is a documented spam target")

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

	# THE OTHER THREE SECTIONS MUST STILL GO. Removing one line from a list of
	# four awaits is a very easy way to remove two.
	for path in ["/api/save", "/api/player/status", "/api/character/inventory"]:
		check("%s is still pushed" % path, src.contains("\"%s\"" % path),
			"this is a skills change, not a save change")

	# THE SEED HAS TO MATCH THE PUSH. _last_pushed is seeded on load so the first
	# save of a session does not push everything; a seed for a section nobody
	# pushes is harmless, but a seed MISSING for one that is pushed makes that
	# section push once per session forever.
	for key in ["save:%d", "status:%d", "inventory:%d"]:
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
	check("the notice names the defense XP cost",
		src.contains("no damage taken, and no defense XP"),
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

	# THE MAINTENANCE NOTICE IS A STATE NOW, NOT ONLY A TOAST.
	check("the closing server counts down on the strip",
		hud.contains("set_world_status(\"maintenance\","),
		"announced once and scrolled away is how somebody is disconnected mid-fight")
	check("and reopening takes it down",
		hud.contains("set_world_status(\"maintenance\", \"\")"))

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
	check("something from minutes ago is just a clock",
		LocalTime.stamp(now - 300) == LocalTime.clock(now - 300),
		LocalTime.stamp(now - 300))
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
		hud.contains("func _push_message(text: String, color: Color, at: int = 0)"),
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
	["res://src/ui/cooking/cookingscreen.gd", "res://scene/ui/cooking/cookingscreen.tscn", "cooking"],
	["res://src/ui/equipment/equipmentpanel.gd", "res://scene/ui/equipment/equipmentpanel.tscn", "equipment"],
	["res://src/ui/friends/friendspanel.gd", "res://scene/ui/friends/friendspanel.tscn", "friends"],
	["res://src/ui/guild/guildpanel.gd", "res://scene/ui/guild/guildpanel.tscn", "guild"],
	["res://src/ui/inventory/inventoryscreen.gd", "res://scene/ui/inventory/inventory.tscn", "inventory"],
	["res://src/ui/kingdom/kingdomboard.gd", "res://scene/ui/kingdom/kingdomboard.tscn", "kingdom"],
	["res://src/ui/lootbag/lootbaginventory.gd", "res://scene/ui/lootbag/lootbaginventory.tscn", "lootbag"],
	["res://src/ui/menus/mapscreen.gd", "res://scene/ui/menus/mapscreen.tscn", "map"],
	["res://src/ui/menus/optionsscreen.gd", "res://scene/ui/menus/optionsscreen.tscn", "options"],
	["res://src/ui/players/playerspanel.gd", "res://scene/ui/players/playerspanel.tscn", "players"],
	["res://src/ui/shop/shopinventory.gd", "res://scene/ui/shop/shopinventory.tscn", "shop"],
	["res://src/ui/staff/staffpanel.gd", "res://scene/ui/staff/staffpanel.tscn", "staff"],
	["res://src/ui/statsscreen.gd", "res://scene/ui/statsscreen.tscn", "stats"],
	["res://src/ui/trade/tradepanel.gd", "res://scene/ui/trade/tradepanel.tscn", "trade"],
]


func _test_panels_are_windows() -> void:
	section("PANELS - drag by the header, resize from any edge, stay reachable")

	# =========================================================================
	# YOU CAN ALWAYS GET IT BACK
	# =========================================================================
	# The whole lost-panel fix, and it is checked first because it is the one
	# defect with no way out from inside the game. clamp_to() is static and pure
	# precisely so this can be asked in one line instead of built in a viewport.
	var screen := Vector2(1920, 1080)
	var panel := Vector2(400, 500)
	var keep: Vector2 = PanelWindow.KEEP_VISIBLE

	var far_right: Rect2 = PanelWindow.clamp_to(Rect2(Vector2(9000, 100), panel), screen)
	check("a panel shoved off the right edge comes back",
		far_right.position.x <= screen.x - keep.x, far_right.position)
	check("and enough of it is left to grab",
		far_right.position.x + panel.x >= keep.x)

	var far_left: Rect2 = PanelWindow.clamp_to(Rect2(Vector2(-9000, 100), panel), screen)
	check("shoved off the left edge, it comes back too",
		far_left.position.x + panel.x >= keep.x, far_left.position)

	var below: Rect2 = PanelWindow.clamp_to(Rect2(Vector2(100, 9000), panel), screen)
	check("dragged off the bottom, the header is still on screen",
		below.position.y <= screen.y - keep.y, below.position)

	# UP IS DIFFERENT FROM DOWN, and that asymmetry is the point. A panel pushed
	# down still shows its top edge, which is the part you grab. Pushed up, the
	# header leaves first and there is nothing underneath it to take hold of.
	var above: Rect2 = PanelWindow.clamp_to(Rect2(Vector2(100, -500), panel), screen)
	check("it can never be pushed above the top of the screen",
		above.position.y >= 0.0, above.position)

	# A PANEL LARGER THAN THE SCREEN is the case that breaks a naive clamp -
	# the allowed range inverts and clampf returns whichever bound it was
	# handed last.
	var huge: Rect2 = PanelWindow.clamp_to(Rect2(Vector2(-50, -50), Vector2(3000, 2000)), screen)
	check("a panel bigger than the screen is still grabbable",
		huge.position.y >= 0.0 and huge.position.x <= screen.x - keep.x
			and huge.position.x + 3000.0 >= keep.x, huge.position)

	# ALREADY ON SCREEN MEANS UNTOUCHED. A clamp that nudges a panel nobody
	# dragged is a panel that drifts.
	var settled: Rect2 = PanelWindow.clamp_to(Rect2(Vector2(300, 200), panel), screen)
	check("a panel already on screen is not moved",
		settled.position == Vector2(300, 200), settled.position)

	check("the grab area is smaller than the smallest panel",
		keep.x <= PanelWindow.MIN_SIZE.x and keep.y <= PanelWindow.MIN_SIZE.y,
		"%s vs %s" % [keep, PanelWindow.MIN_SIZE])
	check("and both are positive",
		keep.x > 0.0 and keep.y > 0.0
			and PanelWindow.MIN_SIZE.x > 0.0 and PanelWindow.MIN_SIZE.y > 0.0)

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
		var resolved := ""
		if marker != -1:
			var line_end: int = scene_text.find("]", marker)
			var line: String = scene_text.substr(marker, line_end - marker)
			var parent_at: int = line.find('parent="')
			if parent_at != -1:
				var from: int = parent_at + 8
				var to: int = line.find('"', from)
				resolved = line.substr(from, to - from) + "/headerpanel"
		check("%s keeps its header where the component looks" % scene_path.get_file(),
			PanelWindow.HEADER_PATHS.has(resolved),
			"found '%s'; known: %s" % [resolved, ", ".join(PanelWindow.HEADER_PATHS)])

	check("sixteen panels are windows", keys_seen.size() == 16, keys_seen.size())

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
# THE 409 IS THE PART MOST LIKELY TO BE "FIXED" BY MISTAKE, so it is pinned here.
# A 409 means "username already taken" everywhere else, and this screen must never
# say that: register() is only ever called one line after a 401, so a 409 cannot
# mean a free name was refused - it can only mean the account exists and the
# password was wrong. Writing the server's own 409 message here would send a
# player off to invent a second username for an account that is already theirs.
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
		for name in ["SAY_WORKING", "SAY_GOOD", "SAY_REFUSED", "SAY_BLOCKED"]:
			check("%s is defined" % name, consts.has(name))
			if consts.has(name) and consts[name] is Color:
				seen.append(consts[name])
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

	# The deliberate deviation, pinned so it survives the next reader.
	check("the 409 is read as a wrong password",
		src.contains("if created.status == 409:") and src.contains("_say(\"Incorrect password.\", SAY_REFUSED)"),
		"here a 409 can only mean the account exists - see the comment there")
	# PER LINE, AND ONLY LINES THAT SPEAK. A whole-file search for the phrase went
	# red on the comment three lines above the branch that explains why the phrase
	# must not be used - the check caught the explanation instead of the mistake.
	# What is actually forbidden is SAYING it, so look only at _say() calls.
	var says_taken: String = ""
	for line in src.split("\n"):
		var lower: String = line.to_lower()
		if not lower.contains("_say("):
			continue
		if lower.contains("already taken") or lower.contains("already exists"):
			says_taken = line.strip_edges()
			break
	check("and the screen never says a name is taken", says_taken == "",
		"that message is true on /register and false in this flow: %s" % says_taken)

	# A ban is not a typo.
	check("403, 429 and 503 are not dressed as typos",
		src.contains("if status == 403 or status == 429 or status == 503:"),
		"none of the three get better by retyping anything")
	check("and a server-side signout lands in the blocked colour",
		src.contains("_say(Api.signout_notice, SAY_BLOCKED)"),
		"a kick read as a failed login is the one player who must not misread it")

	print("  four server answers, four colours; the 409 reading is deliberate")


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
	for name in baked:
		var want: int = int(baked[name])
		if not Element.Type.has(name):
			wrong.append("%s is gone from the enum (data files still say %d)" % [name, want])
			continue
		var got: int = int(Element.Type[name])
		if got != want:
			wrong.append("%s is now %d, but every .tres that says %d means %s"
				% [name, got, want, name])
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
