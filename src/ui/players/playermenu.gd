# playermenu.gd - what you can do with somebody, wherever their name is
# clicked (0.43.0).
#
# The owner: "remember when clicking over a person should have add friend inv
# to guild or party and report button that syncs to our mod/dev/owner same
# thing in chat if i hover over some ones name". Three places show a name: the
# name over a player in the world (remoteplayer.gd), the Players window, and a
# line in chat. All three put these items in their menu, in this order, so a
# name means the same wherever it is:
#
#   Whisper, Add friend, Trade, Invite to party, Invite to guild,
#   then Report: one item per reason.
#
# What each does lives where it already did - the Friends, Trade and Party
# windows, the guild's invite route - and CharacterHUD.player_action() sends
# each item there. A report about a PLAYER goes to POST /api/report/player and
# lands on that player's card on the staff Reports tab, beside any reported
# lines (app.py, report_player()); chat keeps its own "Report this message"
# for a line, which carries the line itself as the evidence.
extends RefCounted
class_name PlayerMenu


const WHISPER := 101
const FRIEND := 102
const TRADE := 103
const PARTY := 104
const GUILD := 105
const REPORT := 120

const REPORT_REASONS := [["spam", "Spam"], ["harassment", "Harassment"], ["hate", "Hate speech"],
	["cheating", "Cheating or scams"], ["other", "Something else"]]


static func fill(menu: PopupMenu, who: String, whisper: bool = true, report: bool = true) -> void:
	"""Add the items for `who` to `menu` (after anything already in it)."""
	if whisper:
		menu.add_item("Whisper", WHISPER)
	menu.add_item("Add friend", FRIEND)
	menu.add_item("Trade", TRADE)
	menu.add_item("Invite to party", PARTY)
	if Party.is_member(who):
		var at: int = menu.get_item_index(PARTY)
		menu.set_item_disabled(at, true)
		menu.set_item_tooltip(at, "Already in your party.")
	menu.add_item("Invite to guild", GUILD)
	if report:
		menu.add_separator("Report %s" % who)
		for i in REPORT_REASONS.size():
			menu.add_item(REPORT_REASONS[i][1], REPORT + i)


static func action_of(id: int) -> Array:
	"""[what, reason] for a menu id: what is whisper, friend, trade, party,
	guild or report (with its reason), or "" for an id not from fill()."""
	match id:
		WHISPER:
			return ["whisper", ""]
		FRIEND:
			return ["friend", ""]
		TRADE:
			return ["trade", ""]
		PARTY:
			return ["party", ""]
		GUILD:
			return ["guild", ""]
	if id >= REPORT and id < REPORT + REPORT_REASONS.size():
		return ["report", REPORT_REASONS[id - REPORT][0]]
	return ["", ""]


static func is_ours(id: int) -> bool:
	return action_of(id)[0] != ""
