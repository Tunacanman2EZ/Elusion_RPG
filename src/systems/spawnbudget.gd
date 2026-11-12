extends RefCounted
# spawnbudget.gd - A WAVE IN PARTS (0.152.0): monsters brought a few a frame,
# never a whole wave in one.
#
# The owner: "lets work on chunking the mini games and measuring everything
# in those". The Descent brought a wave of five in one frame (25-28 ms in the
# container, zz/mgbench), the Endless an elite wave of up to nine, the Forge
# a group of sprites. Every place a minigame brings a wave asks may_bring()
# before each one and says what it took (spent()): the first of a frame is
# always allowed, the rest only while the frame's shared BUDGET_USEC lasts -
# every minigame on one budget, so two waves in one frame share it. What is
# left waits for the next frame, where it is (a mark stays on the floor, a
# queue stays queued): five monsters are five frames apart at worst, a
# twelfth of a second.
#
# A suite that steps a minigame by hand in one frame can switch it off
# (`unlimited`), and every one brought then counts as now.

const BUDGET_USEC := 2000

static var unlimited: bool = false
static var _frame: int = -1
static var _spent: int = 0


static func may_bring() -> bool:
	"""Whether one more monster may be brought this frame."""
	var now: int = Engine.get_process_frames()
	if now != _frame:
		_frame = now
		_spent = 0
		return true
	return unlimited or _spent < BUDGET_USEC


static func spent(usec: int) -> void:
	"""What bringing one took."""
	_spent += maxi(0, usec)
