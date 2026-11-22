# versioncheck.gd - is a newer version of the game live? (0.173.0)
#
# The owner: "the update game is not popping up for pc", and "pc is on
# browser also no need for anyone to download anything really". Nothing told
# a player with the game open that a new version was out: Api.BUILD moves
# only when the game's talk with the server changes, not with each version.
#
# The web deploy (tools/deploy_web.ps1) writes version.txt - DISPLAY_VERSION
# and nothing else - into the build, so it goes live in the same swap as the
# build it names. This asks the page's own address for it FIRST_SECONDS after
# the game starts, every EVERY_SECONDS after, and soon after the tab is
# looked at again; a version newer than this game's own (is_newer()) is kept
# in Api.newer_web_version and said once with `newer_version`. The HUD puts
# line() on its status strip, the login screen says it too (Api.build_notice()).
#
# In a browser only: everybody plays there, and a game run from the editor
# has no page to ask. A child of Api, made in its _ready(). `fetch` is the
# suite's: a Callable(url) -> String that stands in for the request.
extends Node

signal newer_version(version: String)

const FILE := "/version.txt"
const FIRST_SECONDS := 20.0
const EVERY_SECONDS := 300.0
# Looked at again after being away: ask this soon.
const BACK_SECONDS := 2.0

# Where to ask ("" asks nowhere), the newest version heard of, when next.
var url: String = ""
var newest: String = ""
var fetch: Callable = Callable()
var _left: float = FIRST_SECONDS
var _asking: bool = false


static func is_newer(said: String, mine: String) -> bool:
	"""True when version `said` (MAJOR.MINOR.PATCH) is after `mine`. Anything
	that is not three numbers is never newer."""
	var a: PackedStringArray = said.strip_edges().split(".")
	var b: PackedStringArray = mine.strip_edges().split(".")
	if a.size() != 3 or b.size() != 3:
		return false
	for i in 3:
		if not a[i].is_valid_int() or not b[i].is_valid_int():
			return false
	for i in 3:
		if a[i].to_int() != b[i].to_int():
			return a[i].to_int() > b[i].to_int()
	return false


static func line(_version: String) -> String:
	# The owner's words: "an update has been made refresh browser".
	return "An update has been made. Refresh your browser."


func _ready() -> void:
	if url == "" and OS.has_feature("web"):
		var page: String = (load("res://src/systems/webpage.gd") as GDScript).call("origin")
		if page != "":
			url = page + FILE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_left = minf(_left, BACK_SECONDS)


func _process(delta: float) -> void:
	if url == "" or _asking:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = EVERY_SECONDS
	check()


func check() -> void:
	_asking = true
	var body: String = ""
	if fetch.is_valid():
		body = str(await fetch.call(url))
	else:
		body = await _ask(url)
	_asking = false
	note(body)


func note(body: String) -> void:
	"""What version.txt said. A newer version than this game's, not heard of
	before, is kept and said once."""
	var said: String = body.strip_edges()
	# Api's script by path, at the time: it preloads this one.
	var api: GDScript = load("res://src/systems/api.gd") as GDScript
	if not is_newer(said, str(api.get_script_constant_map().get("DISPLAY_VERSION", ""))) or said == newest:
		return
	newest = said
	api.set("newer_web_version", said)
	newer_version.emit(said)


func _ask(where: String) -> String:
	# A NEW ADDRESS EACH TIME (?t=), so no cache along the way answers with
	# the version it kept.
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	if request.request("%s?t=%d" % [where, Time.get_ticks_msec()]) != OK:
		request.queue_free()
		return ""
	var answer: Array = await request.request_completed
	request.queue_free()
	if int(answer[0]) != HTTPRequest.RESULT_SUCCESS or int(answer[1]) != 200:
		return ""
	return (answer[3] as PackedByteArray).get_string_from_utf8()
