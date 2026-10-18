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

# How much of each skill's pending batch the player has been SHOWN, after the
# class specialty and rounded as the server rounds it. See report().
var _shown: Dictionary = {"agility": 0, "defense": 0, "magic": 0}

# The specialty each skill was last reported with, for a batch that comes back.
var _factor: Dictionary = {"agility": 1.0, "defense": 1.0, "magic": 1.0}

# WHOSE XP IT IS (0.56.0). It was sent with the slot playing AT FLUSH TIME, so
# a warrior's last twenty seconds of defense went to the mage picked after
# Switch character - with the mage's specialty on it - and a batch that failed
# before a logout was sent by whoever signed in next. Now `_pending` belongs to
# the account and slot it was earned on: a switch sets it aside to go with its
# own slot (`_set_aside`), and another account forgets it (`_claim()`).
var _pending_user: String = ""
var _pending_slot: int = -1
# [[slot, {skill: raw}], ...] - earned on another slot of the same account.
var _set_aside: Array = []


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = FLUSH_INTERVAL
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_flush_timer)
	add_child(timer)


# Called by player.gd's gain_defense_xp / gain_agility_xp / gain_magic_xp with
# the RAW amount the activity was worth. Accumulated, not sent; the timer sends.
func report(skill: String, raw_amount: int, factor: float = 1.0) -> int:
	"""Queues RAW XP for the server and answers how much of it to SHOW now.

	THE SERVER ROUNDS PER BATCH: proficient_amount() grants int(raw x factor)
	for each batch this sends. player.gd used to round each hit instead, with a
	floor of 1 - so a tank's 1-point hits showed 1 each against the server's
	1.5, the bar ran a third behind, and it jumped at the next login. This
	answers with the batch's int(raw x factor) less what the batch has shown
	already, so the bar and the record agree to the point."""
	if not _pending.has(skill) or raw_amount <= 0:
		return 0
	_claim(CharacterData.active_character_index)
	_factor[skill] = factor
	_pending[skill] = mini(int(_pending[skill]) + raw_amount, PENDING_CAP)
	var due: int = int(float(_pending[skill]) * factor)
	var now: int = maxi(0, due - int(_shown[skill]))
	_shown[skill] = maxi(due, int(_shown[skill]))
	return now


func _on_flush_timer() -> void:
	await flush()


static func _empty() -> Dictionary:
	return {"agility": 0, "defense": 0, "magic": 0}


static func _total(batch: Dictionary) -> int:
	var total: int = 0
	for skill in TRAINABLE:
		total += int(batch.get(skill, 0))
	return total


func _claim(slot: int) -> void:
	"""The buffer, for `slot` of the account signed in now: another account's
	is forgotten (it cannot be sent as theirs), and another slot's is set aside
	to be sent as that slot's."""
	if str(Api.username) != _pending_user:
		_pending = _empty()
		_shown = _empty()
		_set_aside.clear()
		_pending_user = str(Api.username)
		_pending_slot = slot
		return
	if slot != _pending_slot:
		if _pending_slot >= 0 and _total(_pending) > 0:
			_set_aside.append([_pending_slot, _pending])
		_pending = _empty()
		_shown = _empty()
		_pending_slot = slot


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

	# Nothing worth a request - and nothing of another account's.
	_claim(_pending_slot)
	var total: int = _total(_pending)
	for held in _set_aside:
		total += _total(held[1])
	if total <= 0:
		return

	# SNAPSHOT AND ZERO BEFORE THE AWAIT. Activity earned while the request is in
	# flight belongs to the NEXT batch — zeroing after the await would silently
	# drop it. If the post fails in a way a retry could fix, the snapshot is
	# added back below.
	# Each slot's own batch, the one playing now last.
	var batches: Array = _set_aside.duplicate()
	_set_aside.clear()
	if _total(_pending) > 0:
		batches.append([_pending_slot, _pending])
	_pending = _empty()
	# A new batch: the server rounds this one on its own, and so does report().
	_shown = _empty()

	_flushing = true
	var sent_as: String = _pending_user
	for entry in batches:
		await _send(int(entry[0]), entry[1], sent_as)
	_flushing = false


func _send(slot: int, held: Dictionary, sent_as: String) -> void:
	var batch: Dictionary = {
		"agility": int(held.get("agility", 0)),
		"defense": int(held.get("defense", 0)),
		"magic":   int(held.get("magic", 0)),
	}
	var body: Dictionary = {"slot": slot}
	for skill in TRAINABLE:
		body[skill] = batch[skill]

	var res: Dictionary = await Api.post("/api/skill/train", body, TRAIN_TIMEOUT)

	if not res.get("ok", false):
		var status: int = int(res.get("status", 0))
		# RE-BUFFER ONLY WHAT A RETRY COULD FIX. A dropped connection (status 0),
		# a rate limit (429) or a server fault (5xx) will likely succeed next
		# time, so the activity is merged back into whatever arrived during the
		# round trip. A 4xx means the server rejected the request itself — bad
		# slot, expired token, malformed body — and re-sending the identical body
		# would only 4xx again forever, so it is dropped.
		# Back to the slot it was earned on, and only for the same account.
		if (status == 0 or status == 429 or status >= 500) and str(Api.username) == sent_as:
			if slot != _pending_slot:
				_set_aside.append([slot, batch])
				return
			for skill in TRAINABLE:
				_pending[skill] = mini(int(_pending[skill]) + batch[skill], PENDING_CAP)
				# All of it was shown already, as its own batch.
				_shown[skill] = int(float(_pending[skill]) * float(_factor[skill]))
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
