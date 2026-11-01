extends Node
## SIGNING IN WITH GOOGLE, the game's half (0.101.0). The server's half is the
## API's googlesignin/ package; the plan is the commit folder's
## GOOGLE_SIGNIN_PLAN.txt. A player: "Google account to play or I am not
## registering".
##
## Google's sign-in cannot run inside the game, so:
##   1. begin() asks the server for a code (POST /api/auth/google/start, or
##      /api/account/google/link to link an account already signed in) and
##      opens its page in the web browser - the same road in the browser build
##      and the downloaded game.
##   2. The player picks their Google account on that page; the page hands
##      Google's token to the server, which checks it.
##   3. wait_for_page() asks every `poll_every` seconds until the code is done:
##      signed in (the login's own answer), "pick a name" (a new Google
##      account), linked, or refused (a ban, a staff account, run out).
##   4. register() makes the account with the name the player picked.
## The code is this computer's alone: the server lets only the install that
## began it collect it.
##
## Made by whoever shows it (the login screen, Options) as a child, so its
## timers run while they do. Preloaded, no class_name.

const START_PATH := "/api/auth/google/start"
const LINK_PATH := "/api/account/google/link"
const POLL_PATH := "/api/auth/google/poll"
const REGISTER_PATH := "/api/auth/google/register"
# A request with no answer is asked again this many times before giving up.
const NO_ANSWER_TRIES := 5

# The suite's doors: the requests, opening the page, and the wait between asks.
var post_request: Callable = Callable(Api, "post")
var opener: Callable = Callable(self, "_open")
var wait_between: Callable = Callable(self, "_wait")

var code: String = ""
## The short code the page shows too ("K7Q-4MX").
var check: String = ""
var url: String = ""
var poll_every: float = 2.0
var expires_in: float = 600.0
# Moves on at every begin() and cancel(): a wait from before stops.
var _generation: int = 0


func begin(path: String = START_PATH) -> Dictionary:
	"""A code from the server, and its page opened. The server's answer."""
	cancel()
	var res: Dictionary = await post_request.call(path, {}, 0.0)
	var data: Variant = res.get("data", {})
	if not res.get("ok", false) or not (data is Dictionary) or str((data as Dictionary).get("code", "")) == "":
		return res
	code = str(data["code"])
	check = str(data.get("check", ""))
	url = str(data.get("url", ""))
	poll_every = maxf(0.5, float(data.get("poll_every", 2.0)))
	expires_in = float(data.get("expires_in", 600.0))
	open_page()
	return res


func open_page() -> void:
	"""The page in the web browser - again, if the first did not open."""
	if url != "":
		opener.call(url)


func waiting() -> bool:
	return code != ""


func wait_for_page() -> Dictionary:
	"""Asks until the page is done. The last answer: ok with what it is (a
	sign-in, needs_name, linked), a refusal, or {"cancelled": true}."""
	var mine: int = _generation
	var asked: float = 0.0
	var no_answer: int = 0
	while asked <= expires_in + poll_every:
		await wait_between.call(poll_every)
		asked += poll_every
		if mine != _generation:
			return {"ok": false, "cancelled": true}
		var res: Dictionary = await post_request.call(POLL_PATH, {"code": code}, 0.0)
		if mine != _generation:
			return {"ok": false, "cancelled": true}
		var status: int = int(res.get("status", 0))
		if status == 202:
			continue
		if status == 0:
			no_answer += 1
			if no_answer < NO_ANSWER_TRIES:
				continue
		return res
	return {"ok": false, "status": 410, "data": {"message":
		"This sign-in has run out. Press Sign in with Google again."}}


func register(username: String) -> Dictionary:
	"""A new account, for a new Google account, with the name picked."""
	return await post_request.call(REGISTER_PATH, {"code": code, "username": username}, 0.0)


func cancel() -> void:
	_generation += 1
	code = ""
	check = ""
	url = ""


func _open(where: String) -> void:
	OS.shell_open(where)


func _wait(seconds: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout


static func refusal_text(res: Dictionary) -> String:
	"""What to tell the player for an answer that was not a sign-in: the
	server's own words when it gave some."""
	var data: Variant = res.get("data", {})
	if data is Dictionary and data.get("message") is String and str(data["message"]) != "":
		return str(data["message"])
	if int(res.get("status", 0)) == 0:
		return "Could not reach the server. Try again."
	return "Google sign-in did not work. Try again."
