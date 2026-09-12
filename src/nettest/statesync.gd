# statesync.gd — debounced write-back of player stats to the server.
#
# WHY A DEBOUNCE AT ALL: stats change constantly. Hp ticks on every hit, xp on
# every kill, stamina on every frame you sprint. Pushing an HTTP request per
# change would be absurd — and this project has already learned the cheaper
# version of that lesson locally, where saving on every stat change was hitting
# the disk about twenty times a second in normal play. The fix there was a
# debounce; this is the same idea with a network on the other end instead of a
# disk, where the cost of getting it wrong is much higher.
#
# HOW IT WORKS: callers mark fields dirty and carry on. A short timer collapses
# the burst into one request. A scene change calls flush() to force the pending
# write out before the node is freed — which is the case a pure timer would
# lose, because the timer never gets to fire.
#
# THE PART THAT'S EASY TO GET WRONG: a request is in flight for a while, and
# the player keeps playing during it. Marks made while syncing must not be
# swallowed by the response, and a FAILED request must not lose its batch. So
# the batch is snapshotted and cleared before sending, and on failure it is
# merged back WITHOUT overwriting anything newer that arrived meanwhile.
extends Node
class_name StateSync


signal state_changed(state: int, detail: String)
signal synced(status: Dictionary)


enum State {
	CLEAN,    # nothing pending
	DIRTY,    # changes waiting for the debounce to elapse
	SYNCING,  # request in flight
	SYNCED,   # last request succeeded and nothing new since
	FAILED,   # last request failed; the batch is still pending and will retry
}


# How long to wait after the last change before sending. Long enough to
# collapse a burst of combat damage into one request, short enough that a
# crash loses almost nothing.
@export var debounce_seconds: float = 1.5


var _net: NetClient
var _slot: int = 0

# Fields changed since the last successful push. Keyed by the same names the
# server accepts, so this dictionary IS the request body.
var _pending: Dictionary = {}

var _countdown: float = 0.0
var _in_flight: bool = false
var _state: int = State.CLEAN
var _last_error: String = ""

# The most recent authoritative values the server sent back.
var last_status: Dictionary = {}


func configure(net: NetClient, slot: int) -> void:
	_net = net
	_slot = slot


func get_state() -> int:
	return _state


func get_last_error() -> String:
	return _last_error


# =============================================================================
# MARKING
# =============================================================================

func mark(field: String, value: int) -> void:
	_pending[field] = value
	_countdown = debounce_seconds
	if not _in_flight:
		_set_state(State.DIRTY)


func mark_many(fields: Dictionary) -> void:
	for key in fields:
		_pending[key] = fields[key]
	_countdown = debounce_seconds
	if not _in_flight:
		_set_state(State.DIRTY)


func has_pending() -> bool:
	return not _pending.is_empty()


# =============================================================================
# TIMER
# =============================================================================

func _process(delta: float) -> void:
	if _pending.is_empty() or _in_flight:
		return

	_countdown -= delta
	if _countdown <= 0.0:
		flush()


# =============================================================================
# FLUSH
# =============================================================================

func flush() -> void:
	if _net == null or _in_flight or _pending.is_empty():
		return

	# Snapshot and clear BEFORE awaiting. Anything the player changes while
	# this request is in the air lands in a fresh _pending and gets its own
	# flush, rather than being wiped out when this one returns.
	var batch: Dictionary = _pending.duplicate()
	_pending.clear()

	_in_flight = true
	_set_state(State.SYNCING)

	var res: Dictionary = await _net.push_status(_slot, batch)

	_in_flight = false

	if res.ok:
		last_status = res.data
		synced.emit(res.data)
		# More may have arrived during the flight — if so we're dirty again,
		# not synced, and the countdown is already running.
		_set_state(State.DIRTY if not _pending.is_empty() else State.SYNCED)
		return

	_last_error = res.error

	# Put the batch back so it retries — but never over a newer value. If the
	# player took damage again while this request was failing, THAT hp is the
	# truth, not the stale number we tried to send.
	for key in batch:
		if not _pending.has(key):
			_pending[key] = batch[key]

	_countdown = debounce_seconds
	_set_state(State.FAILED)


func _set_state(state: int) -> void:
	if state == _state:
		return
	_state = state
	state_changed.emit(_state, _last_error)


static func state_name(state: int) -> String:
	match state:
		State.CLEAN:   return "idle"
		State.DIRTY:   return "unsaved"
		State.SYNCING: return "saving..."
		State.SYNCED:  return "saved"
		State.FAILED:  return "save failed"
		_:             return "?"
