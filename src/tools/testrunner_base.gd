# testrunner_base.gd - the suite's counters, check(), section(), and the
# helpers and shared constants every part uses. testrunner.gd says how the
# suite is split.
extends Node

# How a name is drawn in every list - checked directly, and through the panels
# that use it. Preloaded, like everywhere else; nametag.gd says why.
const NameTag := preload("res://src/shared/nametag.gd")
const Marks := preload("res://src/shared/marks.gd")
const ApiForTests := preload("res://src/systems/api.gd")
const PoolForTests := preload("res://src/systems/connectionpool.gd")
# The autoloads' scripts, for their static functions: called through the
# autoload itself, the 4.7 editor warns (STATIC_CALLED_ON_INSTANCE).
const _SettingsCode := preload("res://src/systems/settings.gd")
const _CombatCode := preload("res://src/systems/combat.gd")
const _AreaRegistryCode := preload("res://src/systems/arearegistry.gd")


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


# EVERY ERROR THE ENGINE REPORTS, of any kind, while it is attached - for a check
# that some piece of code logs nothing at all. A ConfigFile read with no default
# is one: it returns null and goes on, and the only trace is a line in the log.
class EngineErrorCounter extends Logger:
	var count: int = 0
	var where: PackedStringArray = []
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		count += 1
		if where.size() < 4:
			where.append("%s:%d  %s" % [file.get_file(), line, (rationale if rationale != "" else code).left(90)])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


# THE SUITE PLAYS IN A WORLD OF ITS OWN (game 0.57.1).
#
# It runs in the same user:// folder as the game, so on the owner's PC it read
# HIS options: with a bigger text size and the Pixelify font in options.cfg,
# nine of the GM panel's layout checks failed for no reason in the code. And
# it wrote them - every value came back, but nothing proved it would.
#
# So before the first section the suite points every file of the player's it
# could touch at one of its own - the options, the voice settings, the keys,
# the window layout, the welcome card's "seen" - and starts each from its
# defaults, the way ELUSION_DB points the API's suites at a throwaway
# database. Then _check_the_players_files_untouched() at the end holds it to
# that: every file in user:// that is not the suite's own is as it was.
const SUITE_FILE_PREFIXES := ["_suite", "suite_", "test_"]
var _players_files: Dictionary = {}


func _play_in_a_world_of_its_own() -> void:
	_players_files = _user_files()
	Settings.path = "user://_suite_options.cfg"
	Voice.path = "user://_suite_voice.cfg"
	Keybinds.path = "user://_suite_keys.cfg"
	PanelWindow.layout_path = "user://_suite_panels.cfg"
	ControlsPanel.seen_path = "user://_suite_seen.cfg"
	# The game copy's login files: a remembered session, the devices it was
	# told of, and its install id - which every login on the owner's PC is
	# bound to, so a run that lost it would end them all.
	Api.SESSION_PATH = "user://_suite_session.cfg"
	Api.DEVICES_PATH = "user://_suite_devices.cfg"
	Api.INSTALL_PATH = "user://_suite_install.cfg"
	Api._install_id = ""
	_login_menu_script().set("remembered_path", "user://_suite_remembered.cfg")
	# AND WHAT THE GAME READ FROM THEM AT BOOT, before the suite began. A
	# remembered login is the owner's real token, and the login screen's
	# checks open the screen, which resumes it; a server.cfg sends every
	# request somewhere else. The suite starts signed out, at the default
	# address, as it does on a machine that never ran the game.
	Api.token = ""
	Api.keep_signed_in = false
	Api.staff_unprotected = false
	Api._set_identity("", "player", false)
	Api.BASE_URL = Api.DEFAULT_BASE_URL
	for own in ["_suite_options.cfg", "_suite_voice.cfg", "_suite_keys.cfg", "_suite_panels.cfg", "_suite_seen.cfg",
			"_suite_session.cfg", "_suite_devices.cfg", "_suite_install.cfg", "_suite_remembered.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + own))
	# FROM THE DEFAULTS, whatever the player chose.
	Settings.reset()
	Voice.load_settings()
	Settings.keys.reset_all()


static func _login_menu_script() -> Script:
	return load("res://src/ui/menus/loginmenu.gd") as Script


static func _is_suite_file(file_name: String) -> bool:
	for prefix in SUITE_FILE_PREFIXES:
		if file_name.begins_with(prefix):
			return true
	return false


func _user_files() -> Dictionary:
	"""Every file in user:// that is not the suite's own, by name, with its
	MD5 - leaving out the logs folder, which the engine writes while it runs."""
	var out: Dictionary = {}
	var walk: Array[String] = ["user://"]
	while not walk.is_empty():
		var dir_path: String = walk.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			if dir_path == "user://" and sub == "logs":
				continue
			walk.append(dir_path.path_join(sub))
		for file_name in DirAccess.get_files_at(dir_path):
			if _is_suite_file(file_name):
				continue
			var full: String = dir_path.path_join(file_name)
			out[full] = FileAccess.get_md5(full)
	return out


func _check_the_players_files_untouched() -> void:
	section("THE PLAYER'S FILES - a run leaves them as it found them")
	var now: Dictionary = _user_files()
	var changed: Array = []
	for file_path in _players_files:
		if not now.has(file_path):
			changed.append("%s removed" % str(file_path).get_file())
		elif now[file_path] != _players_files[file_path]:
			changed.append("%s changed" % str(file_path).get_file())
	for file_path in now:
		if not _players_files.has(file_path):
			changed.append("%s made" % str(file_path).get_file())
	check("every file in user:// that is not the suite's own is as it was before the run",
		changed.is_empty(), changed)
	var own_paths: Array = [Settings.path, Voice.path, Keybinds.path, PanelWindow.layout_path, ControlsPanel.seen_path,
		Api.SESSION_PATH, Api.DEVICES_PATH, Api.INSTALL_PATH, str(_login_menu_script().get("remembered_path"))]
	check("  and the suite kept to its own: the options, voice, keys, layout, welcome and login files are its",
		own_paths.all(func(p: String) -> bool: return p.get_file().begins_with("_suite")), own_paths)


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


const READY_SENSITIVE_PROPS := [
	"element", "element_override", "damage", "telegraph_seconds", "is_small",
]


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

	# Five typefaces Options offers (0.8.0, Settings.FONT_STYLES), each by its
	# own authors under the SIL Open Font License 1.1, each in a folder of its
	# own beside its own OFL.txt - five copyright lines, so five licence files.
	# Not Google's, though google/fonts is where every file came from.
	"assets/stylefonts": "ofl-style-fonts",

	# Caio Carlos / Clockwork Raven Studios, purchased under their asset licence.
	# Credit is REQUIRED, not courtesy. The private submodule lives here.
	"art/pack": "clockwork-raven",

	# NOTHING IS "unconfirmed" ANY MORE, and that is the point of leaving this
	# note where the entry used to be. art/thirdparty held one file of unknown
	# origin; it was reachable only from the orphaned old shop scene, so both went.
	# If a folder ever needs that classification again, it means art arrived from
	# a source nobody verified - which is a conversation, not a list entry.
}


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

func _string_characters(line: String, script: bool) -> String:
	# Every character inside a double-quoted string on this line, comments left
	# out (a # outside a string ends a script's line). Escapes are skipped
	# whole, so \" does not end the string.
	var out: String = ""
	var inside: bool = false
	var i: int = 0
	while i < line.length():
		var ch: String = line[i]
		if inside:
			if ch == "\\":
				i += 2
				continue
			if ch == '"':
				inside = false
			else:
				out += ch
		elif ch == '"':
			inside = true
		elif ch == "#" and script:
			break
		i += 1
	return out


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
	# The style fonts (0.8.0): every file Settings.FONT_STYLES names must be
	# here, which _test_text_size_and_font checks.
	"res://assets/stylefonts/pixelifysans/PixelifySans.ttf": "res://assets/stylefonts/pixelifysans",
	"res://assets/stylefonts/tiny5/Tiny5-Regular.ttf": "res://assets/stylefonts/tiny5",
	"res://assets/stylefonts/medievalsharp/MedievalSharp.ttf": "res://assets/stylefonts/medievalsharp",
	"res://assets/stylefonts/imfellenglish/IMFeENrm28P.ttf": "res://assets/stylefonts/imfellenglish",
	"res://assets/stylefonts/grenzegotisch/GrenzeGotisch.ttf": "res://assets/stylefonts/grenzegotisch",
}

const LICENCE_FILENAMES := ["OFL.txt", "OFL", "LICENSE", "LICENSE.txt", "LICENCE", "LICENCE.txt"]


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


func _civil_from_days(days: int) -> Array:
	"""[year, month, day] for days since 1970-01-01: Howard Hinnant's
	days-to-civil, which counts the Gregorian rules out itself (every 4th year,
	not every 100th, every 400th) and shares nothing with Godot's."""
	var z: int = days + 719468
	var era: int = floori((z if z >= 0 else z - 146096) / 146097.0)
	var doe: int = z - era * 146097
	var yoe: int = floori((doe - floori(doe / 1460.0) + floori(doe / 36524.0) - floori(doe / 146096.0)) / 365.0)
	var doy: int = doe - (365 * yoe + floori(yoe / 4.0) - floori(yoe / 100.0))
	var mp: int = floori((5 * doy + 2) / 153.0)
	var day: int = doy - floori((153 * mp + 2) / 5.0) + 1
	var month: int = mp + 3 if mp < 10 else mp - 9
	return [yoe + era * 400 + (1 if month <= 2 else 0), month, day]


func _utc(year: int, month: int, day: int, hour: int = 12, minute: int = 0) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day,
		"hour": hour, "minute": minute, "second": 0}))


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
	["res://src/ui/kills/killrecord.gd", "res://scene/ui/kills/killrecord.tscn", "kills"],
	["res://src/ui/lootbag/lootbaginventory.gd", "res://scene/ui/lootbag/lootbaginventory.tscn", "lootbag"],
	["res://src/ui/menus/creditsscreen.gd", "res://scene/ui/menus/creditsscreen.tscn", "credits"],
	["res://src/ui/menus/mapscreen.gd", "res://scene/ui/menus/mapscreen.tscn", "map"],
	["res://src/ui/menus/optionsscreen.gd", "res://scene/ui/menus/optionsscreen.tscn", "options"],
	["res://src/ui/owner/ownerpanel.gd", "res://scene/ui/owner/ownerpanel.tscn", "owner"],
	["res://src/ui/owner/itemspawner.gd", "res://scene/ui/owner/itemspawner.tscn", "itemspawner"],
	["res://src/ui/owner/savehistory.gd", "res://scene/ui/owner/savehistory.tscn", "savehistory"],
	["res://src/ui/owner/statswindow.gd", "res://scene/ui/owner/statswindow.tscn", "statswindow"],
	["res://src/ui/owner/eventreport.gd", "res://scene/ui/owner/eventreport.tscn", "eventreport"],
	["res://src/ui/owner/landreport.gd", "res://scene/ui/owner/landreport.tscn", "landreport"],
	["res://src/ui/party/partypanel.gd", "res://scene/ui/party/partypanel.tscn", "party"],
	["res://src/ui/players/playerspanel.gd", "res://scene/ui/players/playerspanel.tscn", "players"],
	["res://src/ui/shop/shopinventory.gd", "res://scene/ui/shop/shopinventory.tscn", "shop"],
	["res://src/ui/smith/smithscreen.gd", "res://scene/ui/smith/smithscreen.tscn", "smith"],
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


const FLOOR_COVERAGE_CEILING := 0.30

# The unscaled pool. Every <element>puddle.tscn sizes its own shape from this:
# ice 11.25, earth 12.15, wind 7.2, and so on.
const PUDDLE_BASE_RADIUS := 9.0


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
	_check_the_players_files_untouched()
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

func _any_stackable_item() -> ItemData:
	# get_all_items(), not get_all_ids() — the registry returns the resources.
	for item in ItemRegistry.get_all_items():
		if item != null and item.stackable and item.max_stack > 1:
			return item
	return null


# =============================================================================
# RANKS — the client's half of the server's ordering
# =============================================================================

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
# The fields' monsters since 0.63.0 ("lets double the enemies in big field"),
# and the crypt's skeletons, which are in no band: one solid tier each.
const BIG_FIELD_MONSTERS := 256
const BIG_FIELD_SOLDIERS := 80
const BIG_FIELD_ELITES := 30
# Six in each chamber: "more elites in there also", twice.
const ELITES_A_CHAMBER := 6

# =============================================================================
# THE BIG FIELD, DRESSED (0.61.0)
# =============================================================================
# The owner, 20 Oct: "go ahead and place because i cannot get the right sizes
# for them to do it" - the walls and props of floorwalls.png, in "the alcoves
# and edges", the walls and big pieces solid - and then "i need walls around
# the whole map": every edge of the floor walled (0.62.0) - and the crypt and its
# doors (0.63.0, _test_the_crypt_doors). The sheet is loose pieces of
# every size, not a grid, so a TileSet cannot cut it; scene/crypt/ already
# has each piece at its size, standing on its own feet, and those are what is
# placed (ysortworld/props/crypt, one group an area). These hold the placing
# to what the owner asked and to the fights it must not get in the way of.

const DRESSED_LIGHT_BUDGET := 40


# A body moved by hand is seen by an Area2D a physics step or two later, and
# not always the same number: wait (up to a quarter second) until the door's
# reach has seen the walker arrive or go.
func _door_sees(door: Node, walker: Node, near: bool) -> void:
	for i in 20:
		await get_tree().physics_frame
		if (door.get("_player_nearby") == walker) == near:
			return


# The interact key as a player presses it: down at the start of a frame, so
# the door's own _process sees it "just pressed" in that frame (pressed after
# a timer, it would land after the frame's _process and never be "just"),
# then up, and the physics caught up.
func _press_interact_a_frame() -> void:
	await get_tree().process_frame
	Input.action_press("interact")
	await get_tree().process_frame
	Input.action_release("interact")
	await get_tree().physics_frame
	await get_tree().physics_frame


# =============================================================================
# THE ROAD THROUGH THE GAME (0.15.0)
# =============================================================================
# The owner: "keep both big field -> small field -> gauntlet -> main boss ->
# teleport back to town". Each door is read off its scene, and its landing spot
# looked for in the scene it leads to: a door whose spawn id the next scene does
# not have drops the player at (0, 0) - out of sight of the arrival, and in the
# walls of every area here.
const ROAD := [
	["elusion", "res://src/world/leavetown.gd", "bigfield"],
	["bigfield", "res://src/world/ladder.gd", "field"],
	["field", "res://src/world/ladder.gd", "bossarena"],
	["bossarena", "res://src/world/victoryteleporter.gd", "boss"],
	["boss", "res://src/world/victoryteleporter.gd", "elusion"],
]

# =============================================================================
# THE ARRIVAL PORTAL CLOSES BEHIND YOU (0.15.1)
# =============================================================================
# The owner: "portal took way to long to vanish in big field". It closed on
# body_exited, and a player who lands at the marker stands clear of the
# trigger (the marker 12 px down, the feet 13 px below that, the trigger 25 px
# across), so it never saw them arrive and closed only when walked over. Both
# fields, read off the scenes; then the fix, driven with a stand-in player.

# =============================================================================
# THE DEATH BURST (0.16.0)
# =============================================================================
# Only the Crowned (and the element bosses built on it) and the small poison
# slime were drawn dying; every other monster was there one frame and gone the
# next. Now each of those leaves a DeathBurst (deathburst.gd) - the killing
# hit's flash, a white shape, the shape breaking into pixels - and the website's
# arena plays the deaths, recorded from the game. These hold the burst to what
# it promises: a picture only, the kill itself untouched, and gone in a second.

const SKELETON_BODY := "res://scene/enemy/skeleton.tscn"
const SKELETON_SHEET := "res://art/enemy/skeleton.png"
const SKELETON_SOLDIER := "res://scene/enemy/skeletonsoldier.tscn"
const SKELETON_ELITE := "res://scene/enemy/skeletonelite.tscn"


class SwingDummy extends CharacterBody2D:
	# Stands in for a player in reach of a sword: on the players' layer, in
	# their group, a body and a hurtbox like the warrior's - one player, two
	# shapes - and a take_damage() that writes down what it was given.
	var taken: Array = []

	func _init() -> void:
		collision_layer = 4
		collision_mask = 0
		var feet := CollisionShape2D.new()
		feet.name = "bodyshape"
		var feet_circle := CircleShape2D.new()
		feet_circle.radius = 6.0
		feet.shape = feet_circle
		add_child(feet)
		var hurtbox := Area2D.new()
		hurtbox.name = "hurtbox"
		hurtbox.collision_layer = 4
		hurtbox.collision_mask = 0
		var box := CollisionShape2D.new()
		var box_circle := CircleShape2D.new()
		box_circle.radius = 8.0
		box.shape = box_circle
		hurtbox.add_child(box)
		add_child(hurtbox)
		add_to_group(&"player")

	func take_damage(amount: int, element: int = 0) -> void:
		taken.append([amount, element])


class SwingSync extends Node:
	# Stands in for monstersync.gd as the leader: writes down what it is told.
	var events: Array = []

	func leader_event(_enemy: Node, event: Dictionary) -> void:
		events.append(event)


class RespawnClock extends "res://src/world/enemyrespawner.gd":
	# The respawner with its clock read instead of run: what a death asked for.
	var asked: Array = []

	func _respawn_after(_entry: Dictionary, delay: float) -> void:
		asked.append(delay)


func _opaque_count(img: Image) -> int:
	"""How many pixels of an image are drawn at all."""
	if img == null:
		return -1
	var rgba: Image = img.duplicate() as Image
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = rgba.get_data()
	var n: int = 0
	for i in range(3, bytes.size(), 4):
		if bytes[i] > 0:
			n += 1
	return n


func _crowd_settles_down(crowd: Node, want: int) -> void:
	# Taken away by the clock too: wait until it is down to `want`.
	for i in 400:
		await get_tree().process_frame
		if int(crowd.call("copy_count")) <= want:
			return


func _crowd_settles(crowd: Node, want: int) -> void:
	# Built a batch a frame: wait until it has them all, or stops growing.
	var last: int = -1
	var still: int = 0
	for i in 400:
		await get_tree().process_frame
		var now: int = int(crowd.call("copy_count"))
		if now >= want:
			return
		still = still + 1 if now == last else 0
		last = now
		if still > 30 and now > 0:
			return


# =============================================================================
# THE LARDER AND THE SMITH'S MATERIALS (0.74.0)
# =============================================================================
# The owner: "we have a whole lot of materials and ways to expand cooking in
# clockwork lets get those done", then "Cooking + a smith": monsters drop
# materials that fit them, meals combine several ingredients, heal more and
# give a short buff, and the store sells bait and the cooking staples.
#
# THE IDS ARE WRITTEN OUT HERE, not read off the folders, because the failure
# worth catching is an item that is not there: a .tres with a copy-pasted
# item_id or a bad header is skipped by ItemRegistry without a sound, and a
# list derived from what loaded would shrink with it and still pass.
const LARDER_SMITH := ["ironore", "jadeore", "cobaltore", "amethystore", "emberore",
	"royalgold", "lightessence", "windessence", "iceessence", "wateressence",
	"earthessence", "fireessence", "darkessence", "oldbone", "cursedskull",
	"lightbeholdereye", "windbeholdereye", "icebeholdereye", "waterbeholdereye",
	"earthbeholdereye", "firebeholdereye", "crownedbeholdereye"]
const LARDER_PRODUCE := ["wildherb", "sunberry", "fieldonion", "potato", "frostleaf",
	"snowcap", "riverbean", "lemon", "carrot", "chanterelle", "emberpepper", "pumpkin",
	"shadowcap", "nightberry"]
const LARDER_STAPLES := ["flour", "salt", "egg", "milk", "cheese", "cookingoil", "honey",
	"sugar", "spicemix", "rice"]
# Bait id -> the rolls it gives a cast. The worm is 1.
const LARDER_BAITS := {"lugworm": 2, "glowgrub": 3}
const LARDER_MEALS := ["herbbread", "fishskewer", "sunberrytart", "carpstew",
	"mushroomomelette", "riverbeansoup", "bonebroth", "silverfinpie",
	"chanterellerisotto", "copperscalecurry", "duskfinchowder", "emberroastpumpkin",
	"pumpkinpie", "lemonherbperch", "shadowcapsoup", "azuretangsushi", "nightberrytart",
	"reefclownplatter", "royalbanquet"]
# Which Beholder drops which eye: the last certificate asks for all seven, so
# each must fall from its own boss and from no other monster.
const LARDER_EYES := {"lightboss": "lightbeholdereye", "windboss": "windbeholdereye",
	"iceboss": "icebeholdereye", "waterboss": "waterbeholdereye",
	"earthboss": "earthbeholdereye", "fireboss": "firebeholdereye",
	"boss": "crownedbeholdereye"}


func _larder_expected() -> Dictionary:
	# item_id -> [its art/pack folder, its type, its max stack].
	var expected: Dictionary = {}
	for id in LARDER_SMITH:
		expected[id] = ["materials", ItemData.Type.MATERIAL, 99]
	for id in LARDER_PRODUCE + LARDER_STAPLES:
		expected[id] = ["food", ItemData.Type.MATERIAL, 99]
	for id in LARDER_BAITS:
		expected[id] = ["fishing", ItemData.Type.MATERIAL, 99]
	for id in LARDER_MEALS:
		expected[id] = ["food", ItemData.Type.CONSUMABLE, 20]
	return expected


func _larder_recipe_loops(recipes: Dictionary) -> Array:
	# Every recipe that needs itself through some chain of others: recipes is
	# {meal id: {ingredient id: count}}. Depth first, a meal met again while it
	# is still on the path is the loop. Written here rather than borrowed from
	# the exporter, so the two are separate answers to the same question.
	var loops: Array = []
	var finished: Dictionary = {}
	for start in recipes:
		var path: Array = []
		var on_path: Dictionary = {}
		var stack: Array = [[start, 0]]
		while not stack.is_empty():
			var top: Array = stack[-1]
			var meal_id: String = String(top[0])
			if int(top[1]) == 0:
				if finished.has(meal_id):
					stack.pop_back()
					continue
				path.append(meal_id)
				on_path[meal_id] = true
			var needs: Array = (recipes.get(meal_id, {}) as Dictionary).keys()
			if int(top[1]) < needs.size():
				var next_id: String = String(needs[int(top[1])])
				top[1] = int(top[1]) + 1
				if on_path.has(next_id):
					loops.append(" -> ".join(PackedStringArray(path.slice(path.find(next_id)) + [next_id])))
				elif recipes.has(next_id) and not finished.has(next_id):
					stack.append([next_id, 0])
				continue
			finished[meal_id] = true
			on_path.erase(meal_id)
			path.pop_back()
			stack.pop_back()
	return loops


func _larder_canonical(value: Variant) -> String:
	# One spelling for a value whatever route it took. JSON has no integer type,
	# so a constant read back out of gamedata.json is all floats where the
	# GameConstants original is ints, and a key order can differ; both sides go
	# through the same parse and a sorted stringify before they are compared.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)


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
# puts it back. (Its last page carried the credits until 0.11.1; they are in
# Options > Credits now - _test_the_credits.)

# =============================================================================
# THE CREDITS - Options > Credits (0.11.1)
# =============================================================================
# The owner, 7 Oct: "as for credits i think we should make it a button in
# settings that says credits we can separate artists audio and support there".
# They were the last page of the field's welcome, read once a login. Four tabs
# now: Art, Audio, Support and Engine - the last because Godot's licence, and
# FreeType's, ENet's and Mbed TLS's, ask to be shown in the game.

# WHO EACH OWNER IN LICENSED_ART_FOLDERS IS IN THE CREDITS. A folder of art
# from a new source is classified there first; this makes it a credit too, or
# the suite says whose name is missing.
const CREDITED_OWNERS := {
	"elusion": ["Ahvassa", "Robert - Elusion Studios"],
	"clockwork-raven": ["Caio Carlos - Clockwork Raven Studios"],
	"google-ofl": ["Noto Color Emoji"],
	"ofl-style-fonts": ["Pixelify Sans", "Tiny5", "MedievalSharp", "IM FELL English", "Grenze Gotisch"],
}


func _credit_texts(screen: Node) -> Array:
	"""Every line of text the Credits window is showing, labels and links."""
	var out: Array = []
	for node in screen.page().find_children("*", "", true, false):
		if node is Label or node is LinkButton:
			out.append(str(node.text))
	return out


class MenuHost extends Node:
	var opened: Array = []

	func open_player_menu(who: String) -> void:
		opened.append(who)


class FakeVoiceBridge extends RefCounted:
	var calls: Array = []
	var st: String = "off"
	var outbox: Array = []
	var lv: Dictionary = {"st": "off", "me": 0.0, "peers": {}}
	var mic: bool = false
	var vols: Dictionary = {}
	var started_with: String = ""
	# The settings (0.45.0), and the order the page was told things in.
	var mic_volume: float = 1.0
	var gate: float = 0.0
	var processing: Array = [true, true]
	var order: Array = []

	func start(config_json: String) -> void:
		started_with = config_json
		st = "starting"
		calls.append("start")
		order.append("start")

	func set_mic_volume(volume: float) -> void:
		mic_volume = volume
		order.append("mic_volume")

	func set_gate(level: float) -> void:
		gate = level
		order.append("gate")

	func set_processing(echo: bool, noise: bool) -> void:
		processing = [echo, noise]
		order.append("processing")

	func stop() -> void:
		st = "off"
		calls.append("stop")

	func status() -> String:
		return st

	func reason() -> String:
		return "NotFoundError"

	func dial(id: int) -> void:
		calls.append("dial %d" % id)

	func hear(from_id: int, json: String) -> void:
		calls.append("hear %d %s" % [from_id, json])

	func hangup(id: int) -> void:
		calls.append("hangup %d" % id)

	func set_mic(open: bool) -> void:
		mic = open

	func set_volume(id: int, volume: float) -> void:
		vols[id] = volume

	func take_outbox() -> String:
		var out: String = JSON.stringify(outbox)
		outbox = []
		return out

	func levels() -> String:
		return JSON.stringify(lv)


func _finger_on(target: Control, at: Vector2, down: bool, index: int = 0) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = down
	target.call("_gui_input", touch)


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


# A small HTTP/1.1 server inside the suite, so the connection pool can be
# watched against every way a real server or proxy behaves, with no network.
# mode: "keep" answers and keeps the connection; "close" answers with
# Connection: close and closes half a second later, as Flask's own server
# does, reading nothing more from it; "drop" answers and closes without saying so;
# "eat_next" reads the next request, closes, and goes back to "keep".
# /slow is answered two seconds late; /gz is answered gzip-compressed when asked
# for. /power is a route that wants the password first (STEP-UP, 0.44.0), until
# /api/auth/confirm is sent "right"; /forbidden is a 403 that does not ask for
# it. `heads` keeps each request's headers and `bodies` its body.
class FakeHttpServer extends Node:
	var server := TCPServer.new()
	var port := 0
	var accepted := 0
	var seen: Array[String] = []
	var heads: Array[String] = []
	var bodies: Array[String] = []
	var confirmed := false
	var resume_refusal: Dictionary = {}
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
			var sent_body: String = c.buf.slice(end + 4, end + 4 + length).get_string_from_utf8()
			c.buf = c.buf.slice(end + 4 + length)
			var first := head.get_slice("\r\n", 0)
			seen.append(first.get_slice(" ", 0) + " " + first.get_slice(" ", 1))
			heads.append(head)
			bodies.append(sent_body)
			_answer(c, peer, first.get_slice(" ", 1), head, sent_body)

	func _answer(c: Dictionary, peer: StreamPeerTCP, path: String, head: String, sent_body: String = "") -> void:
		if mode == "eat_next":
			mode = "keep"
			peer.disconnect_from_host()
			_peers.erase(c)
			return
		var body := JSON.stringify({"path": path, "n": seen.size()}).to_utf8_buffer()
		var status_line := "200 OK"
		if path == "/api/auth/confirm":
			var said: Variant = JSON.parse_string(sent_body) if sent_body != "" else null
			confirmed = said is Dictionary and str((said as Dictionary).get("password", "")) == "right"
			if not confirmed:
				status_line = "403 FORBIDDEN"
				body = JSON.stringify({"error": "Forbidden", "message": "That is not your password.",
					"confirm_password": true}).to_utf8_buffer()
		elif path == "/power" and not confirmed:
			status_line = "403 FORBIDDEN"
			body = JSON.stringify({"error": "Forbidden", "message": "Type your password to do this.",
				"confirm_password": true}).to_utf8_buffer()
		elif path == "/forbidden":
			status_line = "403 FORBIDDEN"
			body = JSON.stringify({"error": "Forbidden", "message": "Staff only."}).to_utf8_buffer()
		elif path == "/api/auth/resume" and not resume_refusal.is_empty():
			status_line = "401 UNAUTHORIZED"
			body = JSON.stringify(resume_refusal).to_utf8_buffer()
		var extra := ""
		if path == "/gz" and head.to_lower().contains("accept-encoding: gzip"):
			body = body.compress(FileAccess.COMPRESSION_GZIP)
			extra = "Content-Encoding: gzip\r\n"
		if mode == "close":
			extra += "Connection: close\r\n"
		var out := ("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n%s\r\n"
			% [status_line, body.size(), extra]).to_ascii_buffer()
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


func _aura_patient(parent: Node, at: Vector2, top: int = 200) -> Node2D:
	"""A stand-in player: heal() writes down what it was given."""
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar max_hp: int = 200\nvar is_dying: bool = false\nvar got: Array = []\n" \
		+ "func heal(amount: int) -> void:\n\tgot.append(amount)\n" \
		+ "func aim_ring_feet() -> Vector2:\n\treturn Vector2.ZERO\n"
	script.reload()
	var body := Node2D.new()
	body.set_script(script)
	body.set("max_hp", top)
	parent.add_child(body)
	body.global_position = at
	return body


func _root_layer_z(scene_src: String, layer: String) -> Variant:
	"""The z_index of the root's TileMapLayer named `layer` in a .tscn's text
	(0 when it sets none), or null when there is no such layer."""
	var header: String = "[node name=\"%s\" type=\"TileMapLayer\" parent=\".\"" % layer
	var at: int = scene_src.find(header)
	if at < 0:
		return null
	var block_end: int = scene_src.find("\n\n", at)
	var block: String = scene_src.substr(at, (block_end if block_end >= 0 else scene_src.length()) - at)
	for line in block.split("\n"):
		if line.begins_with("z_index = "):
			return int(line.trim_prefix("z_index = "))
	return 0


# =============================================================================
# THE MONSTERS' THREAT RINGS (0.28.0)
# =============================================================================

const _OFFHAND_TIERS := [["iron", 1], ["jade", 2], ["cobalt", 3], ["amethyst", 4], ["ember", 5]]
const _GRIMOIRES := ["arcanegrimoire", "verdantgrimoire", "sapphiregrimoire"]


class CookingServer extends Node:
	# Answers POST /api/cooking/cook as the server would: one fish fewer in the
	# backpack it is told about, burnt or not in the order given.
	var server := TCPServer.new()
	var port := 0
	var asked: Array = []
	var burns: Array = []
	var bag: Node = null
	var _peers: Array = []

	func start() -> bool:
		for p in range(47200, 47300):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return true
		return false

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			_peers.append({"peer": server.take_connection(), "buf": PackedByteArray()})
		for c in _peers.duplicate():
			var peer: StreamPeerTCP = c.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peers.erase(c)
				continue
			var waiting := peer.get_available_bytes()
			if waiting > 0:
				c.buf.append_array(peer.get_data(waiting)[1])
			var text: String = c.buf.get_string_from_utf8()
			var end := text.find("\r\n\r\n")
			if end == -1:
				continue
			var length := 0
			for h in text.substr(0, end).split("\r\n"):
				if h.to_lower().begins_with("content-length:"):
					length = int(h.get_slice(":", 1).strip_edges())
			if c.buf.size() < end + 4 + length:
				continue
			var body: Variant = JSON.parse_string(c.buf.slice(end + 4, end + 4 + length).get_string_from_utf8())
			c.buf = c.buf.slice(end + 4 + length)
			var id: String = str((body as Dictionary).get("item_id", "")) if body is Dictionary else ""
			asked.append(id)
			var burnt: bool = bool(burns[(asked.size() - 1) % maxi(burns.size(), 1)]) if not burns.is_empty() else false
			var counts: Dictionary = bag.get("counts").duplicate()
			counts[id] = int(counts.get(id, 0)) - 1
			var cells: Array = []
			for k in counts:
				if int(counts[k]) > 0:
					cells.append({"item_id": k, "quantity": int(counts[k])})
			var answer := JSON.stringify({"burnt": burnt, "inventory": cells, "skills": {}}).to_utf8_buffer()
			var out := ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n"
				% answer.size()).to_ascii_buffer()
			out.append_array(answer)
			peer.put_data(out)


class CookingBag extends Node:
	# The backpack the panel reads: counts by item_id.
	var counts: Dictionary = {}

	func get_all_stacks() -> Array[ItemStack]:
		var out: Array[ItemStack] = []
		for id in counts:
			if int(counts[id]) > 0:
				out.append(ItemStack.new(ItemRegistry.get_item(id), int(counts[id])))
		return out

	func get_quantity_of(id: String) -> int:
		return int(counts.get(id, 0))

	func load_server_array(cells: Array) -> void:
		counts.clear()
		for c in cells:
			counts[str(c["item_id"])] = int(counts.get(str(c["item_id"]), 0)) + int(c["quantity"])


class CookingHud extends Node:
	var inventory_screen: Node = null


class CookingCook extends Node:
	var cooking: int = 20
	var cooking_xp: int = 0


# =============================================================================
# THE LARDER, IN THE GAME: MEALS, BUFFS, BAIT, TOOLTIPS (0.74.0)
# =============================================================================
# The owner: cooking should grow past fish, with "meals that combine 2-3
# ingredients, heal more and give a short buff", and "i want to make recipes
# people can make with the food also". The server's half is the API's
# test_larder.py; this is the client's - the cooking window's Recipes tab, the
# FoodBuff autoload and what it moves, the catch naming its bait, and the
# tooltips - against a stand-in server, with stand-in items so it runs in a
# clone without the private art pack.

class LarderServer extends Node:
	# Answers the routes the larder's client talks to, as the server would.
	# /api/cooking/recipe takes the meal's ingredients from the bag it is told
	# about and adds the meal unless it burnt, burns in the order given;
	# /api/character/consume and /api/fishing/catch answer what the test set.
	# Every request is kept, path and body, in the order it came.
	var server := TCPServer.new()
	var port := 0
	var asked: Array = []
	var burns: Array = []
	var bag: Node = null
	var consume_answer: Dictionary = {}
	var catch_answer: Dictionary = {}
	var _peers: Array = []
	var _recipes: int = 0

	func start() -> bool:
		for p in range(47300, 47400):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return true
		return false

	func recipes_asked() -> Array:
		return asked.filter(func(a: Dictionary) -> bool: return a.path == "/api/cooking/recipe")

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			_peers.append({"peer": server.take_connection(), "buf": PackedByteArray()})
		for c in _peers.duplicate():
			var peer: StreamPeerTCP = c.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peers.erase(c)
				continue
			var waiting := peer.get_available_bytes()
			if waiting > 0:
				c.buf.append_array(peer.get_data(waiting)[1])
			while true:
				var text: String = c.buf.get_string_from_utf8()
				var end := text.find("\r\n\r\n")
				if end == -1:
					break
				var length := 0
				var head: PackedStringArray = text.substr(0, end).split("\r\n")
				for h in head:
					if h.to_lower().begins_with("content-length:"):
						length = int(h.get_slice(":", 1).strip_edges())
				if c.buf.size() < end + 4 + length:
					break
				var path: String = head[0].get_slice(" ", 1)
				var body: Variant = JSON.parse_string(c.buf.slice(end + 4, end + 4 + length).get_string_from_utf8())
				c.buf = c.buf.slice(end + 4 + length)
				var answer := JSON.stringify(_answer(path, body if body is Dictionary else {})).to_utf8_buffer()
				var out := ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n"
					% answer.size()).to_ascii_buffer()
				out.append_array(answer)
				peer.put_data(out)

	func _cells(counts: Dictionary) -> Array:
		var cells: Array = []
		for k in counts:
			if int(counts[k]) > 0:
				cells.append({"item_id": k, "quantity": int(counts[k])})
		return cells

	func _answer(path: String, body: Dictionary) -> Dictionary:
		asked.append({"path": path, "body": body})
		if path == "/api/cooking/recipe":
			var id: String = str(body.get("recipe_id", ""))
			var meal: ItemData = ItemRegistry.get_item(id) if ItemRegistry.has_item(id) else null
			var counts: Dictionary = (bag.get("counts") as Dictionary).duplicate() if bag != null else {}
			var burnt: bool = bool(burns[_recipes % burns.size()]) if not burns.is_empty() else false
			_recipes += 1
			var consumed: Array = []
			if meal != null:
				for need in meal.recipe_ingredients:
					counts[need] = int(counts.get(need, 0)) - int(meal.recipe_ingredients[need])
					consumed.append({"item_id": need, "quantity": int(meal.recipe_ingredients[need])})
				if not burnt:
					counts[id] = int(counts.get(id, 0)) + 1
			return {"item_id": id, "burnt": burnt, "output": "" if burnt else id, "inventory": _cells(counts),
				"skills": {}, "consumed": consumed}
		if path == "/api/character/consume":
			return consume_answer.duplicate(true)
		if path == "/api/fishing/catch":
			var caught: Dictionary = catch_answer.duplicate(true)
			caught["inventory"] = _cells((bag.get("counts") as Dictionary).duplicate()) if bag != null else []
			return caught
		return {}


func _larder_item(item_id: String, title: String, tint: Color) -> ItemData:
	# A stand-in with a picture of its own, made here - the real larder's icons
	# are in the private art pack.
	var data := ItemData.new()
	data.item_id = item_id
	data.display_name = title
	data.type = ItemData.Type.MATERIAL
	data.stackable = true
	data.icon_tint = tint
	var picture := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	picture.fill(tint)
	data.icon = ImageTexture.create_from_image(picture)
	return data


func _larder_meal(item_id: String, title: String, tint: Color, ingredients: Dictionary, level: int,
		mastery: int, heal: int, kind: ItemData.BuffKind, amount: int, seconds: int) -> ItemData:
	var meal := _larder_item(item_id, title, tint)
	meal.type = ItemData.Type.CONSUMABLE
	meal.stackable = true
	meal.max_stack = 20
	meal.restore_target = ItemData.RestoreTarget.HP
	meal.restore_amount = heal
	meal.recipe_ingredients = ingredients
	meal.recipe_level = level
	meal.recipe_mastery_level = mastery
	meal.recipe_xp = 10
	meal.buff_kind = kind
	meal.buff_amount = amount
	meal.buff_seconds = seconds
	return meal


func _larder_serve(server: LarderServer) -> Array:
	# Point Api at the stand-in, as the fire's test does. Hands back what to put
	# back afterwards.
	var kept: Array = [ApiForTests.BASE_URL, Api.token, Api.server_online, Api.reachability_known]
	ApiForTests.BASE_URL = "http://127.0.0.1:%d" % server.port
	Api.token = "suite"
	return kept


func _larder_unserve(kept: Array) -> void:
	ApiForTests.BASE_URL = kept[0]
	Api.token = kept[1]
	Api.server_online = kept[2]
	Api.reachability_known = kept[3]


func _larder_wait(fn: Callable, seconds: float) -> void:
	var waited := 0.0
	while not bool(fn.call()) and waited < seconds:
		await get_tree().process_frame
		waited += get_process_delta_time()


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

const SMITH_FIELD := ["zz_smith_blade", "zz_smith_plate", "zz_smith_ore", "zz_smith_bone", "zz_smith_essence"]


func _smith_stand_ins() -> void:
	var blade := ItemData.new()
	blade.item_id = "zz_smith_blade"
	blade.display_name = "Test Blade"
	blade.type = ItemData.Type.WEAPON
	blade.equip_slot = ItemData.EquipSlot.WEAPON
	blade.tier = 1
	blade.value = 500
	blade.damage = 100
	var plate := ItemData.new()
	plate.item_id = "zz_smith_plate"
	plate.display_name = "Test Plate"
	plate.type = ItemData.Type.ARMOR
	plate.equip_slot = ItemData.EquipSlot.CHEST
	plate.tier = 3
	plate.value = 2000
	plate.armor_value = 40
	plate.bonus_max_hp = 20
	var made: Array[ItemData] = [blade, plate]
	for spec in [["zz_smith_ore", "Test Ore"], ["zz_smith_bone", "Test Bone"], ["zz_smith_essence", "Test Essence"]]:
		var stuff := ItemData.new()
		stuff.item_id = spec[0]
		stuff.display_name = spec[1]
		stuff.type = ItemData.Type.MATERIAL
		stuff.stackable = true
		stuff.max_stack = 99
		stuff.value = 30
		stuff.tier = 1
		made.append(stuff)
	for item in made:
		var picture := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		picture.fill(Color(0.7, 0.7, 0.75))
		item.icon = ImageTexture.create_from_image(picture)
		ItemRegistry._items[item.item_id] = item


func _smith_forget_stand_ins() -> void:
	for id in SMITH_FIELD:
		ItemRegistry._items.erase(id)
	for rolled in ItemRegistry._rolled.keys():
		if str(rolled).begins_with("zz_smith_"):
			ItemRegistry._rolled.erase(rolled)


# The stand-in's price list: the SPEC's shapes, the stand-in's materials. Tier
# 1 is anybody's; tier 3 needs the first rank.
const SMITH_TEST_COSTS := [
	{"tier": 1, "materials": [{"item_id": "zz_smith_ore", "quantity": 3}], "certification": 0},
	{"tier": 3, "materials": [{"item_id": "zz_smith_ore", "quantity": 2},
		{"item_id": "zz_smith_bone", "quantity": 1}], "certification": 1},
]
const SMITH_TEST_CERTS := [
	{"rank": 1, "name": "Journeyman Smith", "max_tier": 3, "level": 10, "gold": 5000,
		"materials": [{"item_id": "zz_smith_essence", "quantity": 4}]},
	{"rank": 2, "name": "Artisan Smith", "max_tier": 4, "level": 16, "gold": 25000,
		"materials": [{"item_id": "zz_smith_bone", "quantity": 6}]},
]


class SmithServer extends Node:
	# Answers the smith's four routes and the kingdom's gift as SPEC.md (0.74.0)
	# says the server does, against a bag and a purse of its own: tempering
	# raises every rolled stat by TEMPER_STEP to TEMPER_CAP for the tier's
	# materials and value x TEMPER_GOLD_RATE gold, refuses a Perfect piece, a
	# fully tempered one and a tier above the rank; a certification is the next
	# rank only; a gift burns gold and names a title. Every answer goes out as
	# JSON over a real socket, so the window reads floats where it sent ints,
	# exactly as it does from Flask. `asked` keeps each request as
	# "METHOD /path" and `bodies` what it carried.
	var server := TCPServer.new()
	var port := 0
	var asked: Array = []
	var bodies: Array = []
	var bag: Array = []
	var purse: int = 0
	var rank: int = 0
	var level: int = 30
	var donated: int = 0
	var certify_carries_bag: bool = true
	# The price list: the game's own unless a section hands over its own.
	var costs: Array = GameConstants.TEMPER_COSTS
	var certs: Array = GameConstants.CERTIFICATIONS
	var board_rows: Array = []
	var _peers: Array = []

	func start() -> bool:
		for p in range(47300, 47400):
			if server.listen(p, "127.0.0.1") == OK:
				port = p
				return true
		return false

	func clear() -> void:
		asked.clear()
		bodies.clear()

	func stop() -> void:
		server.stop()
		for c in _peers:
			(c.peer as StreamPeerTCP).disconnect_from_host()
		_peers.clear()

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			_peers.append({"peer": server.take_connection(), "buf": PackedByteArray()})
		for c in _peers.duplicate():
			var peer: StreamPeerTCP = c.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_peers.erase(c)
				continue
			var waiting := peer.get_available_bytes()
			if waiting > 0:
				c.buf.append_array(peer.get_data(waiting)[1])
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
			var sent: String = c.buf.slice(end + 4, end + 4 + length).get_string_from_utf8()
			c.buf = c.buf.slice(end + 4 + length)
			var first := head.get_slice("\r\n", 0)
			var method := first.get_slice(" ", 0)
			var path := first.get_slice(" ", 1)
			var body: Variant = JSON.parse_string(sent) if sent != "" else {}
			asked.append("%s %s" % [method, path.get_slice("?", 0)])
			bodies.append(body if body is Dictionary else {})
			var answer: Array = _route(method, path, body if body is Dictionary else {})
			var out_body := JSON.stringify(answer[1]).to_utf8_buffer()
			var out := ("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n"
				% [answer[0], out_body.size()]).to_ascii_buffer()
			out.append_array(out_body)
			peer.put_data(out)

	func _route(method: String, path: String, body: Dictionary) -> Array:
		var bare: String = path.get_slice("?", 0)
		if method == "GET" and bare == "/api/smith/status":
			return ["200 OK", status()]
		if method == "POST" and (bare == "/api/smith/quote" or bare == "/api/smith/temper"):
			# A CELL THAT DOES NOT HOLD WHAT THE GAME SAW is the game's picture of
			# the bag being out of date: refused, with the bag as it is.
			var cell: int = int(body.get("position", -1))
			var held: Variant = bag[cell] if cell >= 0 and cell < bag.size() else null
			if not (held is Dictionary) or str(held["item_id"]) != str(body.get("item_id", "")):
				return ["409 CONFLICT", {"error": "Conflict",
					"message": "Your backpack changed on the server. It has been reloaded.",
					"resync": {"slot": int(body.get("slot", 0)), "gold": purse, "inventory": bag}}]
			if bare == "/api/smith/quote":
				return ["200 OK", quote(cell, str(body.get("item_id", "")))]
			return temper(cell, str(body.get("item_id", "")))
		if method == "POST" and bare == "/api/smith/certify":
			return certify(int(body.get("rank", 0)))
		if method == "POST" and bare == "/api/kingdom/donate":
			return donate(int(body.get("amount", 0)))
		if method == "GET" and bare == "/api/economy/kingdom":
			return ["200 OK", kingdom()]
		if method == "GET" and bare == "/api/character":
			return ["200 OK", {"inventory": bag}]
		return ["404 NOT FOUND", {"error": "Not Found", "message": "No such route."}]

	func refuse(code: String, message: String) -> Array:
		return [code, {"error": code.get_slice(" ", 1), "message": message}]

	func have(item_id: String) -> int:
		var total := 0
		for cell in bag:
			if cell is Dictionary and str(cell["item_id"]) == item_id:
				total += int(cell["quantity"])
		return total

	func take(item_id: String, count: int) -> void:
		for i in bag.size():
			if count <= 0:
				return
			var cell: Variant = bag[i]
			if cell is Dictionary and str(cell["item_id"]) == item_id:
				var used: int = mini(count, int(cell["quantity"]))
				cell["quantity"] = int(cell["quantity"]) - used
				count -= used
				if int(cell["quantity"]) <= 0:
					bag[i] = null

	func status() -> Dictionary:
		var ranks: Array = []
		for cert in certs:
			var row: Dictionary = (cert as Dictionary).duplicate(true)
			row["earned"] = int(row["rank"]) <= rank
			ranks.append(row)
		var named := ""
		for cert in certs:
			if int(cert["rank"]) == rank:
				named = str(cert["name"])
		var listed: Array = []
		for cost in costs:
			var row: Dictionary = (cost as Dictionary).duplicate(true)
			row["gold_rate"] = GameConstants.TEMPER_GOLD_RATE
			listed.append(row)
		return {"rank": rank, "rank_name": named, "ranks": ranks, "temper_costs": listed,
			"temper_step": GameConstants.TEMPER_STEP, "temper_cap": GameConstants.TEMPER_CAP}

	func tempered_id(item_id: String) -> String:
		var parts: Dictionary = ItemRegistry.split_roll(item_id)
		var base: ItemData = ItemRegistry.get_item(str(parts["base"]))
		var out: String = str(parts["base"]) + GameConstants.QUALITY_MARK
		for pair in ItemRegistry.rolled_fields(base):
			var was: int = int((parts["rolls"] as Dictionary)[pair[1]])
			var now: int = was if was >= GameConstants.TEMPER_CAP \
				else mini(was + GameConstants.TEMPER_STEP, GameConstants.TEMPER_CAP)
			out += "%s%d" % [pair[0], now]
		var resist: Dictionary = parts.get("resist", {})
		if not resist.is_empty():
			out += "%s%d%02d" % [GameConstants.RESIST_LETTER, int(resist["element"]), int(resist["percent"])]
		return out

	func quote(cell: int, item_id: String) -> Dictionary:
		var held: Variant = bag[cell] if cell >= 0 and cell < bag.size() else null
		if not (held is Dictionary) or str(held["item_id"]) != item_id:
			return {"item_id": item_id, "can": false, "reason": "that piece is not in that cell"}
		var data: ItemData = ItemRegistry.get_item(item_id)
		var parts: Dictionary = ItemRegistry.split_roll(item_id)
		var cost: Dictionary = {}
		for row in costs:
			if int(row["tier"]) == int(data.tier):
				cost = row
		var base: ItemData = ItemRegistry.get_item(str(parts.get("base", item_id)))
		var gold: int = maxi(1, roundi(float(base.value) * GameConstants.TEMPER_GOLD_RATE))
		var mats: Array = []
		for need in cost.get("materials", []):
			mats.append({"item_id": need["item_id"], "quantity": need["quantity"], "have": have(str(need["item_id"]))})
		var new_id: String = tempered_id(item_id) if not (parts.get("rolls", {}) as Dictionary).is_empty() else item_id
		var answer := {"item_id": item_id, "new_item_id": new_id,
			"before": parts.get("rolls", {}), "after": ItemRegistry.split_roll(new_id).get("rolls", {}),
			"gold": gold, "materials": mats, "certification": int(cost.get("certification", 0)),
			"can": true, "reason": ""}
		var why := ""
		if data.is_perfect():
			why = "already perfect"
		elif new_id == item_id:
			why = "fully tempered"
		elif rank < int(cost.get("certification", 0)):
			why = "you need to be certified for tier %d" % int(data.tier)
		else:
			for m in mats:
				if int(m["have"]) < int(m["quantity"]):
					why = "you are missing %s" % ItemRegistry.get_item(str(m["item_id"])).display_name
					break
			if why == "" and purse < gold:
				why = "you need %d gold" % gold
		if why != "":
			answer["can"] = false
			answer["reason"] = why
		return answer

	func temper(cell: int, item_id: String) -> Array:
		var q: Dictionary = quote(cell, item_id)
		if not bool(q.get("can", false)):
			return refuse("403 FORBIDDEN", str(q.get("reason", "no")))
		for m in q["materials"]:
			take(str(m["item_id"]), int(m["quantity"]))
		purse -= int(q["gold"])
		bag[cell] = {"item_id": q["new_item_id"], "quantity": 1}
		return ["200 OK", {"item_id": q["new_item_id"], "position": cell, "gold": purse,
			"status": status(), "inventory": bag, "consumed": q["materials"]}]

	func certify(wanted: int) -> Array:
		if wanted != rank + 1:
			return refuse("409 CONFLICT", "Earn the ranks in order.")
		var cert: Dictionary = {}
		for row in certs:
			if int(row["rank"]) == wanted:
				cert = row
		if cert.is_empty():
			return refuse("404 NOT FOUND", "There is no such rank.")
		if level < int(cert["level"]):
			return refuse("403 FORBIDDEN", "You need to be level %d." % int(cert["level"]))
		for m in cert["materials"]:
			if have(str(m["item_id"])) < int(m["quantity"]):
				return refuse("404 NOT FOUND", "You are missing %s." % ItemRegistry.get_item(str(m["item_id"])).display_name)
		if purse < int(cert["gold"]):
			return refuse("403 FORBIDDEN", "You need %d gold." % int(cert["gold"]))
		for m in cert["materials"]:
			take(str(m["item_id"]), int(m["quantity"]))
		purse -= int(cert["gold"])
		rank = wanted
		var answer: Dictionary = status()
		if certify_carries_bag:
			answer["gold"] = purse
			answer["inventory"] = bag
		return ["200 OK", answer]

	func title_for(total: int) -> Array:
		var title := ""
		var next_title := ""
		var next_at := 0
		for row in GameConstants.PATRON_TITLES:
			if total >= int(row["at"]):
				title = str(row["title"])
			elif next_title == "":
				next_title = str(row["title"])
				next_at = int(row["at"])
		return [title, next_title, next_at]

	func donate(amount: int) -> Array:
		if amount < GameConstants.DONATION_MINIMUM:
			return refuse("400 BAD REQUEST", "The Crown takes gifts of at least %d gold." % GameConstants.DONATION_MINIMUM)
		if amount > purse:
			return refuse("403 FORBIDDEN", "You do not carry that much.")
		purse -= amount
		donated += amount
		var t: Array = title_for(donated)
		return ["200 OK", {"donated": donated, "title": t[0], "next_title": t[1], "next_at": t[2], "gold": purse}]

	func kingdom() -> Dictionary:
		var t: Array = title_for(donated)
		var top: Array = board_rows.duplicate(true)
		var mine: Dictionary = {"username": "suite", "contributed": donated, "lusions": 0, "deaths": 0,
			"lost": 0, "rank": 1, "donated": donated, "title": t[0], "next_title": t[1], "next_at": t[2]}
		var found := false
		for row in top:
			if str(row.get("username", "")) == "suite":
				row["contributed"] = donated
				row["title"] = t[0]
				found = true
		if not found and donated > 0:
			top.push_front({"username": "suite", "contributed": donated, "lusions": 0, "deaths": 0,
				"lost": 0, "rank": 1, "title": t[0]})
		return {"total": 1000000 + donated, "total_taxed": 0, "total_deaths": 3, "total_lost": 0,
			"by_reason": {"shop_buy": 1000000, "donation": donated}, "contributors": top.size(),
			"top": top, "you": mine}


class SmithHud extends Node:
	# What the smith window and the anvil ask the HUD for: the bag, through the
	# inventory screen, and open_smith(), which this only counts.
	var inventory_screen: Node = null
	var opened: Array = []

	func open_smith(anvil: Node, who: Node) -> void:
		opened.append([anvil, who])


class SmithPlayer extends Node2D:
	# The purse and the level the window reads, and set_gold() as Player has it.
	var gold: int = 0
	var level: int = 12

	func set_gold(total: int) -> void:
		gold = total


func _smith_stage(server: SmithServer) -> Dictionary:
	"""A stand-in HUD with a real bag in it, a player, and the smith window, all
	pointed at `server`. Returns what was built so the section can take it down."""
	var huds: Array = get_tree().get_nodes_in_group(&"hud")
	for h in huds:
		h.remove_from_group(&"hud")
	var hud := SmithHud.new()
	hud.add_to_group(&"hud")
	add_child(hud)
	var screen := Node.new()
	hud.add_child(screen)
	hud.inventory_screen = screen
	var bag := GridContainer.new()
	bag.set_script(load("res://src/ui/inventory/inventorycontainer.gd"))
	bag.set("grid_width", 6)
	bag.set("grid_height", 5)
	bag.name = "inventorycontainer"
	screen.add_child(bag)
	bag.owner = screen
	bag.unique_name_in_owner = true
	# THE CARRY, as the inventory screen marks it: what tells the grid that a
	# re-read of it is /api/character and not the bank's /api/account.
	bag.set("is_carry", true)
	bag.load_server_array(server.bag)
	var player := SmithPlayer.new()
	player.gold = server.purse
	player.level = server.level
	add_child(player)
	var layer := CanvasLayer.new()
	add_child(layer)
	var window: Control = (load("res://scene/ui/smith/smithscreen.tscn") as PackedScene).instantiate() as Control
	layer.add_child(window)
	return {"huds": huds, "hud": hud, "bag": bag, "player": player, "layer": layer, "window": window}


func _smith_unstage(stage: Dictionary) -> void:
	(stage.layer as Node).queue_free()
	(stage.player as Node).queue_free()
	(stage.hud as Node).queue_free()
	for h in stage.huds:
		if is_instance_valid(h):
			h.add_to_group(&"hud")


func _cell_id(bag: Node, cell: int) -> String:
	var stack: ItemStack = bag.get_stack_at(cell)
	return str(stack.data.item_id) if stack != null and stack.data != null else ""


func _texts_under(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.find_children("*", "Label", true, false):
		out.append((child as Label).text)
	return out


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

func _own_member_shadows(file: String, text: String) -> Array[String]:
	var lines: PackedStringArray = text.split("\n")
	var member_re := RegEx.new()
	member_re.compile("^(@\\w+(\\([^)]*\\))?\\s+)*(static\\s+var|var|const)\\s+([A-Za-z_]\\w*)")
	var word_re := RegEx.new()
	word_re.compile("^[A-Za-z_]\\w*")
	var members: Dictionary = {}
	var in_class: bool = false
	var in_doc: bool = false
	for i in lines.size():
		var line: String = lines[i]
		if line.count("\"\"\"") % 2 == 1:
			in_doc = not in_doc
			continue
		if in_doc or line == "" or line.begins_with("#") or line.begins_with("\t") or line.begins_with(" "):
			continue
		in_class = line.begins_with("class ")
		var hit: RegExMatch = member_re.search(line) if not in_class else null
		if hit != null:
			members[hit.get_string(4)] = i + 1
	var out: Array[String] = []
	in_class = false
	in_doc = false
	var at: int = 0
	while at < lines.size():
		var line: String = lines[at]
		if line.count("\"\"\"") % 2 == 1:
			in_doc = not in_doc
			at += 1
			continue
		if in_doc:
			at += 1
			continue
		if line != "" and not line.begins_with("\t") and not line.begins_with(" ") and not line.begins_with("#"):
			in_class = line.begins_with("class ")
		if in_class:
			at += 1
			continue
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("func ") or trimmed.begins_with("static func "):
			var head: String = trimmed
			var last: int = at
			while head.count("(") > head.count(")") and last + 1 < lines.size():
				last += 1
				head += " " + lines[last].strip_edges()
			for param in _param_names(head):
				if members.has(param):
					out.append("%s:%d  parameter '%s' hides the member at line %d" % [file.replace("res://", ""), at + 1, param, members[param]])
			at = last + 1
			continue
		if line.begins_with("\t") or line.begins_with(" "):
			for prefix in ["var ", "const ", "for "]:
				if trimmed.begins_with(prefix):
					var hit: RegExMatch = word_re.search(trimmed.substr(prefix.length()))
					if hit != null and members.has(hit.get_string()):
						out.append("%s:%d  %s'%s' hides the member at line %d" % [file.replace("res://", ""), at + 1, prefix, hit.get_string(), members[hit.get_string()]])
		at += 1
	return out


func _param_names(head: String) -> Array[String]:
	"""The names in a function's parameter list: what each comma-separated
	piece at the outermost depth starts with."""
	var names: Array[String] = []
	var open_at: int = head.find("(")
	if open_at == -1:
		return names
	var depth: int = 0
	var piece: String = ""
	for ch in head.substr(open_at + 1):
		if ch in ["(", "[", "{"]:
			depth += 1
		elif ch in [")", "]", "}"]:
			if depth == 0:
				_add_param_name(names, piece)
				break
			depth -= 1
		elif ch == "," and depth == 0:
			_add_param_name(names, piece)
			piece = ""
			continue
		piece += ch
	return names


func _add_param_name(names: Array[String], piece: String) -> void:
	var param: String = piece.strip_edges().get_slice(":", 0).get_slice("=", 0).strip_edges()
	if param != "":
		names.append(param)


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


func _guild_rows_of(panel: Node) -> Array:
	var out: Array = []
	for child in panel.rows.get_children():
		if not child.is_queued_for_deletion():
			out.append(child)
	return out


func _marks_of(node: Node) -> Array:
	# Every drawn mark under `node` (marks.gd's "mark" meta), in tree order:
	# the dots, arrows and rank marks that used to be letters.
	var out: Array = []
	if node == null:
		return out
	for child in node.find_children("*", "", true, false):
		if child is Control and child.is_visible_in_tree() and child.has_meta("mark"):
			out.append(str(child.get_meta("mark")))
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

func _staff_trade(state: String, at: int) -> Dictionary:
	return {"trade_id": "abcdef1234567890", "state": state, "at": at, "opened_at": at - 60,
		"character": "Aldra", "with": "rowdy", "with_name": "Rowan",
		"gave": [{"item_id": "petboss", "quantity": 1}], "got": [], "gold_gave": 0,
		"gold_got": 1500, "tax": 75 if state == "done" else 0}


func _trade_panel_script() -> Script:
	# The trade window's statics, which the desk borrows its wording from.
	return load("res://src/ui/trade/tradepanel.gd") as Script


# =============================================================================
# FRIENDS — the header: a title, a line in words, and one ×
# =============================================================================
# The header had a boxed "R" beside a boxed "x" in a style nothing else used,
# and said "0 online of 0" to somebody with no friends. It is the guild
# header's shape now; the list re-reads itself, so there is no R.

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


func _rarity_test_item(item_id: String, tier: int, type: int = ItemData.Type.ARMOR) -> ItemData:
	var d := ItemData.new()
	d.item_id = item_id
	d.display_name = "Test %s" % item_id
	d.tier = tier
	d.type = type as ItemData.Type
	d.max_stack = 99
	d.stackable = true
	return d


# =============================================================================
# SHARED MONSTERS (0.7.0) - one game runs them, everyone fights them
# =============================================================================
# 6 Oct, the owner: "shared monsters separate loot bags". The game that leads an
# area runs its monsters; every other game draws them as mirrors, sends its
# hits to the leader, and reports its own kill when one it hit dies. These run
# the real monstersync.gd against a stand-in for the presence link, a leader
# first and then a follower, each in a world of its own - two in one tree would
# share the "enemies" group and each would count the other's monsters.

class FakeLink extends Node:
	signal lead_changed(area: String, leader_id: int, sharers: int)
	signal world_received(data: Dictionary)
	signal hits_received(from_id: int, hits: Array)
	signal world_needed(for_id: int)
	var me: int = 1
	var open: bool = true
	var n: int = 1
	var leader: int = -2
	var area: String = ""
	var sent_world: Array = []
	var sent_hits: Array = []
	var asked: int = 0

	func shares() -> bool:
		return open

	func my_id() -> int:
		return me

	func sharers() -> int:
		return n

	func leader_for(a: String) -> int:
		return leader if a == area else -2

	func send_world(data: Dictionary, to: int = -1) -> void:
		# THROUGH JSON, as the wire does: numbers come back floats, and a test
		# that kept the original ints would never see a missing int().
		sent_world.append([JSON.parse_string(JSON.stringify(data)), to])

	func send_hits(hits: Array) -> void:
		sent_hits.append(JSON.parse_string(JSON.stringify(hits)))

	func request_world() -> void:
		asked += 1

	# The server's two messages to a leader, as this stand-in delivers them.
	func deliver_hits(from_id: int, hits: Array) -> void:
		hits_received.emit(from_id, hits)

	func deliver_need(for_id: int) -> void:
		world_needed.emit(for_id)


const SM_AREA := "smtestarea"


func _sm_world() -> Node2D:
	"""A tiny area: a y-sort world with a container of placed monsters, a
	projectiles container and a ground container, named the same every time
	so its monsters' origin keys match from one world to the next."""
	var world := Node2D.new()
	world.name = "smworld"
	add_child(world)
	var enemies := Node2D.new()
	enemies.name = "enemies"
	world.add_child(enemies)
	for spec in [["fs1", "res://scene/enemy/firesprite.tscn", Vector2(-20000, -20000)],
			["sn1", "res://scene/enemy/bushsniper.tscn", Vector2(-20100, -20000)]]:
		var e: Node2D = (load(spec[1]) as PackedScene).instantiate()
		e.name = spec[0]
		e.position = spec[2]
		enemies.add_child(e)
	var shots := Node2D.new()
	shots.name = "shots"
	shots.add_to_group("projectiles")
	world.add_child(shots)
	var ground := Node2D.new()
	ground.name = "ground"
	ground.add_to_group("groundeffects")
	world.add_child(ground)
	return world


func _sm_sync(link: Node) -> Node:
	var sync: Node = (load("res://src/world/monstersync.gd") as GDScript).new()
	sync.link = link
	sync.area_id = SM_AREA
	return sync


func _sm_last_world(link: Node) -> Dictionary:
	return (link.sent_world.back()[0] as Dictionary) if not link.sent_world.is_empty() else {}


class BooksLink extends FakeLink:
	var keeps_books: bool = true

	func books() -> bool:
		return open and keeps_books


func _sm_hits(world: Dictionary) -> Array:
	var out: Array = []
	for hit in world.get("hits", []):
		out.append([int(hit[0]), int(hit[1]), int(hit[2])])
	return out


func _opaque_size(texture: Texture2D) -> Vector2:
	"""How big the art in `texture` is: its non-clear pixels' bounds."""
	if texture == null:
		return Vector2.ZERO
	var image: Image = texture.get_image()
	return Vector2(image.get_used_rect().size) if image != null else Vector2.ZERO


func _mage_const(constant: String) -> Variant:
	return (load("res://src/characters/mage.gd") as GDScript).get_script_constant_map().get(constant)


func _attack_wall(parent: Node, centre: Vector2, size: Vector2, layer: int) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = layer
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	parent.add_child(wall)
	wall.global_position = centre
	return wall


func _hero_against(parent: Node, cls: String, wall_bottom: float, x: float) -> Node2D:
	# A class's real scene, its body touching a wall from the south the way a
	# walk into it leaves it. Its own brain is off: the test drives it.
	var hero: Node2D = (load("res://scene/characters/%s.tscn" % cls) as PackedScene).instantiate()
	parent.add_child(hero)
	hero.set_physics_process(false)
	var feet: CollisionShape2D = hero.get_node_or_null("bodyshape") as CollisionShape2D
	var offset: Vector2 = feet.position if feet != null else Vector2.ZERO
	var reach: float = 0.0
	if feet != null and feet.shape is CircleShape2D:
		reach = (feet.shape as CircleShape2D).radius
	elif feet != null and feet.shape is CapsuleShape2D:
		reach = (feet.shape as CapsuleShape2D).height * 0.5
	hero.global_position = Vector2(x, wall_bottom + reach + 0.5 - offset.y)
	return hero


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


const _BOSS_BAND := {"lightboss": 1, "windboss": 1, "waterboss": 2, "iceboss": 2,
	"earthboss": 3, "fireboss": 4, "boss": 5}


func _boss_scene_path(enemy_id: String) -> String:
	# The Crowned is the bare scene; it takes boss.tres in _ready().
	return "res://scene/enemy/bossenemy.tscn" if enemy_id == "boss" \
		else "res://scene/enemy/%s.tscn" % enemy_id


const _KIT_BOSSES := ["lightboss", "windboss", "waterboss", "iceboss", "earthboss", "fireboss", "boss"]
const _KNOWN_SHAPES := [&"ring", &"cage", &"gate", &"lance", &"cross", &"spiral", &"carpet",
	&"arc", &"triwall", &"rake", &"snare", &"ladder", &"sweep", &"checker"]


func _kit_boss(enemy_id: String) -> Node:
	var boss: Node = (load(_boss_scene_path(enemy_id)) as PackedScene).instantiate()
	if boss.enemy_data == null:
		boss.enemy_data = boss.ENEMY_DATA
	return boss


# BOSSES THAT SCALE (0.80.0). The owner: "we need to think outside the box ...
# lets fix it up" - a boss's health set by who fights it. The server's half is
# test_combatbook.py CB-12.

func _stand_in_with_health() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node2D\nvar hp: int = 0\nvar max_hp: int = 0\n"
	script.reload()
	return script


func _gear_test_item(item_id: String, slot: int, fields: Dictionary) -> ItemData:
	var d := ItemData.new()
	d.item_id = item_id
	d.display_name = item_id.capitalize()
	d.equip_slot = slot as ItemData.EquipSlot
	for f in fields:
		d.set(f, fields[f])
	return d


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


func _menu_item(id: String, type: int, slot: int = 0, stack: int = 1) -> ItemData:
	var item := ItemData.new()
	item.item_id = id
	item.display_name = id
	item.type = type as ItemData.Type
	item.equip_slot = slot as ItemData.EquipSlot
	item.stackable = stack > 1
	item.max_stack = stack
	return item


class ZoneDummy extends Node2D:
	# Stands in for this game's player: a body point, a take_damage() that
	# writes down what it was given, and is_dying.
	var taken: Array = []
	var is_dying: bool = false

	func _init() -> void:
		var body := Node2D.new()
		body.name = "bodyshape"
		body.position = Vector2(0, 13)
		add_child(body)

	func take_damage(amount: int, element: int = 0) -> void:
		taken.append([amount, element])


func _root_property(scene_path: String, property: StringName) -> Variant:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var state: SceneState = packed.get_state()
	for p in state.get_node_property_count(0):
		if state.get_node_property_name(0, p) == property:
			return state.get_node_property_value(0, p)
	return null


static func _is_suite_script(path: String) -> bool:
	"""Whether `path` is one of the suite's own scripts (testrunner.gd and its
	parts, testrunner_*.gd), which a scan of the game's code leaves out."""
	return path.begins_with("res://src/tools/") and path.get_file().begins_with("testrunner")
