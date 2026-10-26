extends Node
## errorreporter.gd - the game tells the server what broke in it (0.88.0).
##
## THE OWNER RATED STABILITY 8 OF 10 - "rare live breakages, and fixes go out
## fast" - and asked for the 9. A SCRIPT ERROR in a player's game printed to a
## console nobody reads, and the game played on half broken; the owner heard of
## it only if the player told him. Now every script error is caught here, and
## once a minute the ones this game hit go to POST /api/client/errors - where
## (the script and the line), what it said, how many times, the version and
## the area. The GM panel's Health tab lists them for the owner, worst first,
## with how many players hit each - never who.
##
## A CHILD OF THE Api AUTOLOAD (Api._ready() adds it), so it lives as long as
## the game does and sends with Api's own requests. Preloaded, no class_name,
## so a fresh checkout needs no editor rescan.
##
## WHAT IT CATCHES: Logger.ERROR_TYPE_SCRIPT only - the errors a broken script
## raises. Not push_error() or push_warning(): the game says those on purpose,
## and an engine error about a missing file on one machine is not a breakage
## everybody shares. Godot may call a Logger from any thread, so the counts
## sit behind a Mutex.
##
## NOT IN THE EDITOR (wanted()): the owner sees his own errors there, and the
## suite runs with the editor's binary - its errors are the suite's business,
## and a test that provokes one must not post it to whatever server is
## running. The suite turns it on by hand, with a stand-in for the request.

## How often what was caught is sent, in seconds.
const REPORT_SECONDS := 60.0
## At most this many different errors a report (the server keeps 20); the
## rest wait for the next one.
const ERRORS_PER_REPORT := 20
## At most this many different errors held between reports. Past it a new one
## is counted in `lost` and not kept - a loop raising a new message every frame
## must not grow this without end.
const ERRORS_HELD := 200
## The longest message kept; the server keeps 400.
const WHAT_MOST := 400
## The request's own timeout. A report is never worth waiting long for.
const REPORT_TIMEOUT := 8.0

## What sends a report: (path, body) -> Dictionary, Api.post by default. The
## suite swaps it.
var send: Callable = Callable()
## Whether a report may go now: logged in, by default. The suite swaps it.
var can_send: Callable = Callable()

var _catcher: Catcher = null
var _timer: Timer = null
var _sending := false
## Different errors that did not fit in ERRORS_HELD since the game started.
var lost := 0


class Catcher extends Logger:
	## where|what -> [where, what, count]; filled on any thread.
	var held: Dictionary = {}
	var order: Array = []
	var lost := 0
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT:
			return
		note(place(file, line), rationale if rationale != "" else code)

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func note(where: String, what: String) -> void:
		what = what.strip_edges().replace("\n", " ").replace("\t", " ").left(WHAT_MOST)
		if what == "":
			return
		var key := where + "|" + what
		_lock.lock()
		if held.has(key):
			held[key][2] = int(held[key][2]) + 1
		elif held.size() < ERRORS_HELD:
			held[key] = [where, what, 1]
			order.append(key)
		else:
			lost += 1
		_lock.unlock()

	## Up to `most` errors, oldest first, taken out of what is held.
	func take(most: int) -> Array:
		var out: Array = []
		_lock.lock()
		while not order.is_empty() and out.size() < most:
			var key: String = order.pop_front()
			var entry: Array = held[key]
			held.erase(key)
			out.append({"where": entry[0], "what": entry[1], "count": int(entry[2])})
		_lock.unlock()
		return out

	## Put a report that could not be sent back, ahead of anything newer.
	func give_back(entries: Array) -> void:
		_lock.lock()
		for i in range(entries.size() - 1, -1, -1):
			var entry: Dictionary = entries[i]
			var key: String = str(entry["where"]) + "|" + str(entry["what"])
			if held.has(key):
				held[key][2] = int(held[key][2]) + int(entry["count"])
			elif held.size() < ERRORS_HELD:
				held[key] = [entry["where"], entry["what"], int(entry["count"])]
				order.push_front(key)
			else:
				lost += 1
		_lock.unlock()

	func waiting() -> int:
		_lock.lock()
		var n := order.size()
		_lock.unlock()
		return n

	## The server's pattern for a place: res://... or the engine's <word>.
	static func place(file: String, line: int) -> String:
		if file == "":
			return "<engine>"
		if not file.begins_with("res://"):
			# Never a path off this computer: it could carry the player's name.
			return "<" + file.get_file().get_basename().left(40).validate_filename() + ">" \
				if file.get_file() != "" else "<engine>"
		return "%s:%d" % [file, line] if line > 0 else file


## Whether this game reports at all: not in the editor (nor so in the suite).
static func wanted() -> bool:
	return not OS.has_feature("editor")


func _ready() -> void:
	if not wanted():
		return
	start()


## Catch and report from now on. _ready() calls it outside the editor; the
## suite calls it by hand.
func start() -> void:
	if _catcher != null:
		return
	_catcher = Catcher.new()
	OS.add_logger(_catcher)
	_timer = Timer.new()
	_timer.wait_time = REPORT_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(report_now)
	add_child(_timer)


## Stop catching. The suite's way out; a game never stops.
func stop() -> void:
	if _catcher != null:
		OS.remove_logger(_catcher)
		_catcher = null
	if _timer != null:
		_timer.queue_free()
		_timer = null


func catcher() -> Catcher:
	return _catcher


func _exit_tree() -> void:
	stop()


## The report as the server reads it, or {} when there is nothing to say.
func next_report(area: String) -> Dictionary:
	if _catcher == null:
		return {}
	var errors: Array = _catcher.take(ERRORS_PER_REPORT)
	if errors.is_empty():
		return {}
	return {"version": Api.DISPLAY_VERSION, "area": area, "errors": errors}


## Send what was caught, if anything and if this game may. Answers whether a
## report went and the server took it.
func report_now() -> bool:
	if _catcher == null or _sending or _catcher.waiting() == 0:
		return false
	var allowed: bool = can_send.call() if can_send.is_valid() else Api.is_logged_in()
	if not allowed:
		return false
	var area: String = ""
	if is_instance_valid(AreaRegistry) and AreaRegistry.has_method("current_area_id"):
		area = str(AreaRegistry.current_area_id())
	if not area.is_valid_identifier() and area != "":
		area = ""
	var body := next_report(area.to_lower())
	if body.is_empty():
		return false
	_sending = true
	var res: Dictionary = {}
	if send.is_valid():
		res = await send.call("/api/client/errors", body)
	else:
		res = await Api.post("/api/client/errors", body, REPORT_TIMEOUT)
	_sending = false
	if not is_instance_valid(self) or not is_inside_tree():
		return false
	if bool(res.get("ok", false)):
		return true
	# NOT TAKEN: the server down, or this game signed out - kept for the next.
	# A 400 is a report the server will never take, and a 404 a server from
	# before 0.88.0 that takes none: neither is kept, to be refused again.
	if not (int(res.get("status", 0)) in [400, 404]) and _catcher != null:
		_catcher.give_back(body["errors"])
	return false
