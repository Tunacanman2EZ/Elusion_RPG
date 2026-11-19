# payanswer.gd - what a minigame's screen says when the server does not pay
# a run, and whether asking again could change it (0.168.8).
#
# The owner, stuck on Crownfall's results: "issue trying to leave the game".
# Each paying screen (the Healer's Run, Cut the Cloth, Crownfall, the
# Beholder's Table) said "Could not reach the server" for any answer but a
# payment, and Leave only asked again - so an answer that would always be no
# (signed out, a run the server will not pay) kept the screen up for good.
# Now the screen says what happened, and after a refusal, or a second try
# that failed, Leave goes without the gold. A run worth nothing leaves at once.
extends RefCounted


static func why_not(res: Dictionary) -> String:
	"""The answer in words: no answer, signed out, busy, broken, or the
	server's own reason for saying no."""
	var status: int = int(res.get("status", 0))
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	var said: String = str(data.get("message", "")).strip_edges()
	if status <= 0:
		return "No answer from the server."
	if status == 401:
		return "You were signed out, so the server could not pay this run."
	if status == 408 or status == 429:
		return "The server is busy - try again in a moment."
	if status >= 500:
		return "The server had a problem paying this run."
	if said != "":
		return "The server would not pay this run: %s" % said
	return "The server would not pay this run."


static func refused(res: Dictionary) -> bool:
	"""An answer asking again would only get again: a 4xx, but not 408 (too
	slow) or 429 (too many)."""
	var status: int = int(res.get("status", 0))
	return status >= 400 and status < 500 and status != 408 and status != 429


static func waiting_line(going_without: bool) -> String:
	"""What Leave does next."""
	if going_without:
		return "Leave again to go without its gold."
	return "Your gold is waiting: Leave again to try once more."


static func not_paid_line(game_name: String, why: String) -> String:
	"""A Leave without the gold, in words for the HUD."""
	return "%s: this run's gold was not paid. %s" % [game_name, why]
