extends RefCounted
## What a browser build asks of the page it runs in.
##
## Every function here is safe on the desktop: with no page, each one does
## nothing or answers "". Preloaded rather than a class_name, like nametag.gd,
## so a fresh checkout compiles the files that use it without an editor rescan.


static func in_browser() -> bool:
	return OS.has_feature("web")


static func origin() -> String:
	"""The page's own address - scheme, host and port - or "" with no page."""
	if not in_browser():
		return ""
	var value: Variant = JavaScriptBridge.eval("window.location.origin", true)
	return "" if value == null else str(value)


static func mark_ready() -> void:
	"""Tells web/shell.html the game is drawing, so its loader can step aside.

	Until then the loader covers the canvas - including the engine's own boot
	splash - so the page goes from the loader straight to the login screen."""
	if in_browser():
		JavaScriptBridge.eval("window.elusionReady && window.elusionReady()", true)


static func watch_leaving(on_leaving: Callable) -> Array:
	"""Calls `on_leaving` when the page is hidden (another tab, a minimised
	window, a phone locking) or unloaded (the tab closed, a reload).

	Returns the two callbacks, and the caller MUST keep them: a callback
	JavaScriptBridge made is dropped with its last reference and simply stops
	firing, which looks exactly like the event never happening.

	Hidden counts as leaving because a hidden page draws no frames - the engine
	runs on the browser's frame callback - and a page closed from the tab strip
	is hidden first. Unloaded is kept as well for browsers that skip that."""
	if not in_browser():
		return []
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	var document: JavaScriptObject = JavaScriptBridge.get_interface("document")
	if window == null or document == null:
		return []
	var on_visibility := func(_args: Array) -> void:
		if str(document.visibilityState) == "hidden":
			on_leaving.call()
	var on_unload := func(_args: Array) -> void:
		on_leaving.call()
	var hidden: JavaScriptObject = JavaScriptBridge.create_callback(on_visibility)
	var unloading: JavaScriptObject = JavaScriptBridge.create_callback(on_unload)
	document.addEventListener("visibilitychange", hidden)
	window.addEventListener("pagehide", unloading)
	return [hidden, unloading]


static func pick_file(accept: String, on_picked: Callable) -> Array:
	"""Opens the browser's own file picker; `on_picked` is called with the
	chosen file's (bytes, name). `accept` is the input's filter (".png,.jpg").

	GODOT'S FileDialog IN A BROWSER SHOWS THE ENGINE'S VIRTUAL DISK - a folder
	of nothing - since a page cannot list the player's files. The page's own
	<input type="file"> can, and hands back only the one file chosen.

	Returns what the caller MUST keep until the file arrives: the input and its
	two callbacks (see watch_leaving())."""
	if not in_browser():
		return []
	var document: JavaScriptObject = JavaScriptBridge.get_interface("document")
	if document == null:
		return []
	var input: JavaScriptObject = document.createElement("input")
	input.type = "file"
	input.accept = accept
	# IN THE PAGE, NOT FLOATING: a detached input's click() opened no picker
	# under Playwright's Chromium, and Safari has long wanted it attached too.
	input.style.display = "none"
	document.body.appendChild(input)
	var chosen: Dictionary = {"name": ""}
	var on_bytes := func(args: Array) -> void:
		if args.is_empty():
			return
		on_picked.call(JavaScriptBridge.js_buffer_to_packed_byte_array(args[0]), str(chosen["name"]))
	var got_bytes: JavaScriptObject = JavaScriptBridge.create_callback(on_bytes)
	var on_change := func(_args: Array) -> void:
		var files: JavaScriptObject = input.files
		if files == null or int(files.length) == 0:
			return
		var file: JavaScriptObject = files.item(0)
		chosen["name"] = str(file.name)
		file.arrayBuffer().then(got_bytes)
		input.remove()
	var changed: JavaScriptObject = JavaScriptBridge.create_callback(on_change)
	input.addEventListener("change", changed)
	input.click()
	return [input, got_bytes, changed]


static func send_now(url: String, method: String, headers: PackedStringArray, body: String) -> bool:
	"""Sends a request the browser finishes even after the page is gone.

	HTTPRequest cannot do this. It starts its fetch from _process(), on the
	NEXT frame, and a page that is hidden or closing has no next frame - so a
	save handed to it then waits for the player to come back, or is lost with
	the tab. This is fetch() with keepalive, started before this returns.

	The browser holds at most 64 KB of keepalive bodies in flight. A save is a
	few KB; past the limit the fetch is refused and nothing else changes."""
	if not in_browser():
		return false
	var named: Dictionary = {}
	for line in headers:
		var colon: int = line.find(":")
		if colon > 0:
			named[line.substr(0, colon).strip_edges()] = line.substr(colon + 1).strip_edges()
	# EVERY VALUE GOES IN AS JSON, which is also a JavaScript literal, so
	# nothing in a body or a token can end the string it sits in.
	var script: String = ("fetch(%s, {method: %s, headers: %s, body: %s, keepalive: true})"
		+ ".catch(function () {}); true") % [
		JSON.stringify(url), JSON.stringify(method), JSON.stringify(named), JSON.stringify(body)]
	return JavaScriptBridge.eval(script, true) == true
