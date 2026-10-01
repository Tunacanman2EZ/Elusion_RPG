# connectionpool.gd - the desktop game's connections to the server, kept open
# and reused. Api owns one (api.gd, _pool) and sends every JSON request through
# it; pictures and the browser build still use HTTPRequest.
#
# WHY. HTTPRequest opens a new connection for every request and closes it after.
# On the real server that is a TCP handshake and a TLS handshake before the
# request itself: three round trips where one would do. Measured on day 1 at a
# 50 ms ping and 60 fps, over plain HTTP: 133 ms a request, against 54 ms on a
# connection that stayed open. Every kill, loot take, purchase, bank move, chat
# line and save waits on one of these. A browser keeps its connections open by
# itself, which is why the browser build does not need this.
#
# HOW. Up to MAX_LINES connections, each carrying one request at a time; a
# request waits in a queue while all of them are busy. Each frame, _process()
# moves every connection as far as the bytes that have arrived allow, so an
# answer is read in the frame it lands rather than a step a frame. A
# connection unused for IDLE_CLOSE_SECONDS is closed by us, well before any
# server or proxy would close it (nginx 75 s, waitress 120 s, Caddy 5 min), so
# a request almost never goes out on a connection the far end already dropped.
#
# WHEN ONE IS DROPPED ANYWAY. A connection checked just before use and found
# closed is reopened, and nothing has been sent. A connection that dies after
# the request went out, before any answer, is the case that matters: the server
# may or may not have acted on it. A GET is asked again once on a new
# connection, because asking twice changes nothing. Anything else - a purchase,
# a loot take, a kill report - is never sent twice; it fails as "no answer",
# the same as a lost connection always has.
#
# The answer is the array HTTPRequest's request_completed carries -
# [result, response_code, headers, body] - so Api reads it with the same code.
extends Node

const MAX_LINES := 6
const IDLE_CLOSE_SECONDS := 20.0
# Steps per connection per frame. A request goes from sent to fully read in a
# handful; the cap only bounds a frame against a misbehaving peer.
const STEPS_PER_FRAME := 64


class Job extends RefCounted:
	signal done(result: Array)
	var method: int
	var path: String
	var headers: PackedStringArray
	var body: PackedByteArray
	var deadline_ms: int
	var host: String
	var port: int
	var tls: bool
	var prefix: String
	var retried := false
	var result: Array = []


class Line extends RefCounted:
	var client := HTTPClient.new()
	var host := ""
	var port := 0
	var tls := false
	var job: Job = null
	var stage := ""        # "", "connecting", "requesting", "reading"
	var reused := false
	var used_ms := 0
	var code := 0
	var response_headers := PackedStringArray()
	var received := PackedByteArray()


# The suite shortens this; nothing else changes it.
var idle_close_seconds := IDLE_CLOSE_SECONDS
var _queue: Array[Job] = []
var _lines: Array[Line] = []
# How many connections were opened, for the suite and the perf overlay.
var connections_opened := 0


func _ready() -> void:
	# A paused tree must not stall the network: a save on the pause menu still
	# has to land.
	process_mode = Node.PROCESS_MODE_ALWAYS


static func parse_base_url(base_url: String) -> Dictionary:
	"""{tls, host, port, prefix} for an address like https://host:8443/game, or
	{} for one this cannot use."""
	var url := base_url.strip_edges()
	var tls := false
	if url.begins_with("https://"):
		tls = true
		url = url.substr(8)
	elif url.begins_with("http://"):
		url = url.substr(7)
	else:
		return {}
	var slash := url.find("/")
	var authority := url if slash == -1 else url.substr(0, slash)
	var prefix := "" if slash == -1 else url.substr(slash)
	while prefix.ends_with("/"):
		prefix = prefix.substr(0, prefix.length() - 1)
	var host := authority
	var port := 443 if tls else 80
	if authority.begins_with("["):
		var close := authority.find("]")
		if close == -1:
			return {}
		host = authority.substr(1, close - 1)
		if authority.substr(close + 1).begins_with(":"):
			port = int(authority.substr(close + 2))
	elif authority.contains(":"):
		host = authority.get_slice(":", 0)
		port = int(authority.get_slice(":", 1))
	if host == "" or port <= 0 or port > 65535:
		return {}
	return {"tls": tls, "host": host, "port": port, "prefix": prefix}


func send(base_url: String, method: int, path: String, headers: PackedStringArray,
		body: PackedByteArray, timeout: float) -> Job:
	"""Queue a request, and start it if a connection is free. Await the returned
	job's `done` for the answer; it is always emitted deferred, so it cannot
	fire before the caller is awaiting it."""
	var job := Job.new()
	var where := parse_base_url(base_url)
	job.method = method
	job.path = path
	job.headers = headers
	job.body = body
	job.deadline_ms = Time.get_ticks_msec() + int(timeout * 1000.0)
	if where.is_empty():
		job.result = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	else:
		job.host = where.host
		job.port = where.port
		job.tls = where.tls
		job.prefix = where.prefix
		if not headers_have(headers, "accept-encoding"):
			job.headers.append("Accept-Encoding: gzip")
	_queue.append(job)
	# STARTED NOW when a connection is free: waiting for _process() would add a
	# frame to every request. Nothing can answer inside this call (see _finish).
	if job.result.is_empty() and _queue.size() == 1:
		var line := _free_line_for(job)
		if line != null:
			_queue.pop_front()
			_start(line, job)
			for i in STEPS_PER_FRAME:
				if line.job != job or not _step(line):
					break
	return job


static func keeps_open(response_headers: PackedStringArray) -> bool:
	for h in response_headers:
		var lower := h.to_lower()
		if lower.begins_with("connection:") and lower.contains("close"):
			return false
	return true


static func headers_have(headers: PackedStringArray, header: String) -> bool:
	for h in headers:
		if h.to_lower().begins_with(header + ":"):
			return true
	return false


func busy() -> bool:
	if not _queue.is_empty():
		return true
	for line in _lines:
		if line.job != null:
			return true
	return false


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	# Answers already decided (a bad address) leave on the next frame, never in
	# send() itself.
	for job in _queue.duplicate():
		if not job.result.is_empty():
			_queue.erase(job)
			job.done.emit.call_deferred(job.result)
		elif now > job.deadline_ms:
			# Still waiting for a connection when its time ran out.
			_queue.erase(job)
			job.done.emit.call_deferred([HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()])
	for line in _lines:
		if line.job == null and line.stage == "" and line.client.get_status() != HTTPClient.STATUS_DISCONNECTED \
				and now - line.used_ms > idle_close_seconds * 1000.0:
			line.client.close()
	while not _queue.is_empty():
		var line := _free_line_for(_queue[0])
		if line == null:
			break
		_start(line, _queue.pop_front())
	for line in _lines:
		if line.job == null:
			continue
		if now > line.job.deadline_ms:
			# The answer may still arrive on this connection, and the next
			# request on it would read it as its own. So the connection goes too.
			line.client.close()
			_finish(line, [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()])
			continue
		for i in STEPS_PER_FRAME:
			if line.job == null or not _step(line):
				break


func _free_line_for(job: Job) -> Line:
	# An open connection to the same place first, then any idle one, then a new
	# one while there is room.
	var idle: Line = null
	for line in _lines:
		if line.job != null:
			continue
		if line.host == job.host and line.port == job.port and line.tls == job.tls \
				and line.client.get_status() == HTTPClient.STATUS_CONNECTED:
			return line
		if idle == null:
			idle = line
	if idle != null:
		return idle
	if _lines.size() < MAX_LINES:
		var fresh := Line.new()
		_lines.append(fresh)
		return fresh
	return null


func _start(line: Line, job: Job) -> void:
	line.job = job
	line.code = 0
	line.response_headers = PackedStringArray()
	line.received = PackedByteArray()
	var same_place := line.host == job.host and line.port == job.port and line.tls == job.tls
	if same_place and line.client.get_status() == HTTPClient.STATUS_CONNECTED:
		# CHECKED JUST BEFORE USE: a connection the far end closed while idle
		# shows up here, before anything is sent on it.
		line.client.poll()
	if same_place and line.client.get_status() == HTTPClient.STATUS_CONNECTED:
		line.reused = true
		_send_on(line)
		return
	line.reused = false
	_open(line)


func _open(line: Line) -> void:
	var job := line.job
	line.client.close()
	line.host = job.host
	line.port = job.port
	line.tls = job.tls
	var err := line.client.connect_to_host(job.host, job.port, TLSOptions.client() if job.tls else null)
	if err != OK:
		_finish(line, [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()])
		return
	connections_opened += 1
	line.stage = "connecting"


func _send_on(line: Line) -> void:
	var job := line.job
	var err := line.client.request_raw(job.method, job.prefix + job.path, job.headers, job.body)
	if err != OK:
		_lost_before_answer(line)
		return
	line.stage = "requesting"


func _step(line: Line) -> bool:
	"""One move along a request. True when something changed, so the caller
	steps again in the same frame; false to wait for the next frame."""
	var client := line.client
	client.poll()
	var status := client.get_status()
	match line.stage:
		"connecting":
			match status:
				HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
					return false
				HTTPClient.STATUS_CONNECTED:
					_send_on(line)
					return true
				HTTPClient.STATUS_CANT_RESOLVE:
					_finish(line, [HTTPRequest.RESULT_CANT_RESOLVE, 0, PackedStringArray(), PackedByteArray()])
				HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
					_finish(line, [HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, PackedStringArray(), PackedByteArray()])
				_:
					_finish(line, [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()])
			return false
		"requesting":
			if status == HTTPClient.STATUS_REQUESTING:
				return false
			if client.has_response():
				line.code = client.get_response_code()
				line.response_headers = client.get_response_headers()
				line.stage = "reading"
				return true
			_lost_before_answer(line)
			return false
		"reading":
			var length := client.get_response_body_length()
			if status == HTTPClient.STATUS_BODY:
				var chunk := client.read_response_body_chunk()
				if chunk.is_empty():
					return false
				line.received.append_array(chunk)
				if length < 0 or line.received.size() < length:
					return true
			# ALL OF IT ARRIVED is the test, not the connection's state. A server
			# that closes after answering (Flask's own does, every time) makes
			# HTTPClient report a connection error the moment the last byte has
			# been read - with the whole answer in hand.
			var complete := length >= 0 and line.received.size() >= length
			if complete or status == HTTPClient.STATUS_CONNECTED or status == HTTPClient.STATUS_DISCONNECTED:
				var answer := _answer(line)
				# A SERVER THAT SAYS IT WILL CLOSE, WILL. Flask's own server
				# answers "Connection: close" to everything, and HTTPClient can
				# still read CONNECTED for a moment after the last byte. Sent on
				# then, the next request went nowhere until its timeout.
				if not keeps_open(line.response_headers):
					line.client.close()
				_finish(line, answer)
			else:
				_finish(line, [HTTPRequest.RESULT_CONNECTION_ERROR, 0, PackedStringArray(), PackedByteArray()])
			return false
	return false


func _lost_before_answer(line: Line) -> void:
	# The connection went before any answer. On a connection that had already
	# carried a request, that is very likely the far end having closed it as the
	# request went out. A GET is safe to ask again; nothing else is.
	var job := line.job
	line.client.close()
	if line.reused and not job.retried and job.method == HTTPClient.METHOD_GET:
		job.retried = true
		line.reused = false
		_open(line)
		return
	_finish(line, [HTTPRequest.RESULT_CONNECTION_ERROR, 0, PackedStringArray(), PackedByteArray()])


func _answer(line: Line) -> Array:
	var body := line.received
	for h in line.response_headers:
		if h.to_lower().begins_with("content-encoding:") and h.to_lower().contains("gzip"):
			body = body.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
			if body.is_empty() and not line.received.is_empty():
				return [HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED, line.code, line.response_headers, PackedByteArray()]
	return [HTTPRequest.RESULT_SUCCESS, line.code, line.response_headers, body]


func _finish(line: Line, result: Array) -> void:
	var job := line.job
	line.job = null
	line.stage = ""
	line.used_ms = Time.get_ticks_msec()
	if job != null:
		# Deferred, so an answer decided while the caller is still inside
		# send() reaches it after it has started to await.
		job.done.emit.call_deferred(result)
