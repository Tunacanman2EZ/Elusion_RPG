# skilltrainer.gd — buffers server-owned training XP (defense, agility, magic)
# and posts it to /api/skill/train.
#
# WHY AN AUTOLOAD, AND WHY A BUFFER
# ---------------------------------
# These three skills are server-owned now: the client no longer decides how much
# of them a character has (see SERVER_OWNED_SKILLS in app.py, and E-2 in
# SECURITY_NOTES.md). The client's job is to REPORT the activity — damage taken,
# distance sprinted, spells landed — and let the server grant it, bound it to
# what is physically earnable, and store the result. That is the same split
# combat.gd made for kills: the client says what happened, the server says what
# it was worth.
#
# But a kill is one event with one round trip. Training XP arrives as a fine
# drizzle — a few points per hit, per sprint tick, per spell — many times a
# minute. A request per drop would flood the server and the wire, so the drops
# are accumulated here and posted in one batch on a timer.
#
# It lives in an autoload rather than in player.gd for the same reason combat.gd
# does: the player node is rebuilt on every scene change, and a buffer that died
# with it would drop the defense XP earned in the field the moment you walked to
# town. An autoload is always in the tree — it holds the buffer across scenes and
# can wait out a network round trip without being freed mid-await.
#
# THE CLIENT STILL LEVELS UP LOCALLY, OPTIMISTICALLY. player.gd's gain_*_xp()
# still moves the bar and fires the popup the instant the XP is earned, so the
# game stays immediate. What changed is that the local number is no longer the
# record — the server's grant is, and it loads next session. An honest player,
# whose reported activity always sits under the server's deliberately generous
# per-second ceiling, sees the same number in both places and never notices the
# handoff. A client that lies gets clamped server-side and quietly corrected on
# the next load, exactly the way a cheated kill count is. See combat.gd's
# _apply_xp() for the same reasoning spelled out.
extends Node


# The skills this reports. attack is server-owned too, but it rides on
# /api/combat/kill — a kill IS its activity — and fishing and cooking have their
# own endpoints for the same reason. Only these three have no natural event of
# their own, which is why they need a generic report channel.
const TRAINABLE := ["agility", "defense", "magic"]

# How often the buffer is posted. Long enough that a normal session makes a
# handful of requests rather than a stream; short enough that little is lost if
# the game closes without a clean flush. The server caps the credited window at
# MAX_TRAIN_ELAPSED_SECONDS (60s) regardless, so a much longer interval would
# only throw honest XP away.
const FLUSH_INTERVAL := 20.0

# Same budget as a kill report (combat.gd's KILL_TIMEOUT): a request the player
# caused, but not one they are watching a spinner over.
const TRAIN_TIMEOUT := 4.0

# A ceiling on any single pending skill. Far above any honest 60s of activity —
# so it never clamps a real player — and far below the server's billion-point
# STAT_CEILING, so a very long offline stretch of re-buffered failures can never
# grow a value into the range the server rejects outright rather than clamps.
const PENDING_CAP := 10_000_000


# raw, PRE-proficiency amounts waiting to be sent. The server applies class
# proficiency itself (SKILL_PROFICIENCY in app.py); reporting an already-scaled
# number would double it. player.gd scales its LOCAL copy for the popup and
# reports the raw amount here — equal for a class with no bonus, and
# deliberately different for one that has.
var _pending: Dictionary = {"agility": 0, "defense": 0, "magic": 0}

# Guards against a second flush starting while one is in flight — the timer can
# fire again during a slow round trip.
var _flushing: bool = false


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = FLUSH_INTERVAL
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_flush_timer)
	add_child(timer)


# Called by player.gd's gain_defense_xp / gain_agility_xp / gain_magic_xp with
# the RAW amount the activity was worth — the same number those functions scale
# for their own optimistic level-up. Accumulated, not sent; the timer sends.
func report(skill: String, raw_amount: int) -> void:
	if not _pending.has(skill):
		return
	if raw_amount <= 0:
		return
	_pending[skill] = mini(int(_pending[skill]) + raw_amount, PENDING_CAP)


func _on_flush_timer() -> void:
	await flush()


# Posts whatever has accumulated and clears it. Public so a logout or a clean
# shutdown can force one last send rather than waiting on the timer.
func flush() -> void:
	if _flushing:
		return
	if not Api.is_logged_in():
		return
	# Already known down — don't spend a timeout, and don't touch the buffer:
	# the activity is still real and rides on the next flush that gets through.
	if Api.is_known_offline():
		return

	# Nothing worth a request.
	var total: int = 0
	for skill in TRAINABLE:
		total += int(_pending.get(skill, 0))
	if total <= 0:
		return

	# SNAPSHOT AND ZERO BEFORE THE AWAIT. Activity earned while the request is in
	# flight belongs to the NEXT batch — zeroing after the await would silently
	# drop it. If the post fails in a way a retry could fix, the snapshot is
	# added back below.
	var batch: Dictionary = {
		"agility": int(_pending["agility"]),
		"defense": int(_pending["defense"]),
		"magic":   int(_pending["magic"]),
	}
	_pending = {"agility": 0, "defense": 0, "magic": 0}

	_flushing = true

	var body: Dictionary = {"slot": CharacterData.active_character_index}
	for skill in TRAINABLE:
		body[skill] = batch[skill]

	var res: Dictionary = await Api.post("/api/skill/train", body, TRAIN_TIMEOUT)
	_flushing = false

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		# RE-BUFFER ONLY WHAT A RETRY COULD FIX. A dropped connection (status 0),
		# a rate limit (429) or a server fault (5xx) will likely succeed next
		# time, so the activity is merged back into whatever arrived during the
		# round trip. A 4xx means the server rejected the request itself — bad
		# slot, expired token, malformed body — and re-sending the identical body
		# would only 4xx again forever, so it is dropped.
		if status == 0 or status == 429 or status >= 500:
			for skill in TRAINABLE:
				_pending[skill] = mini(int(_pending[skill]) + batch[skill], PENDING_CAP)
		if OS.is_debug_build():
			print("[TRAIN] flush failed (%d) — %s" % [status, res.get("error", "")])
		return

	# The server has granted and stored the XP; its rows are the record. The
	# client does NOT force its display to the returned levels — an honest
	# player's optimistic bar already matches, and snapping to a value computed
	# from a batch that is a round trip behind would only jitter it backward.
	# The load path reconciles for real on the next session, which is the one
	# place a clamped cheat visibly corrects. Same contract as combat.gd.
	if OS.is_debug_build():
		var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
		print("[TRAIN] flushed a:%d d:%d m:%d — %s" % [
			batch["agility"], batch["defense"], batch["magic"],
			JSON.stringify(data.get("skills", {}))])
