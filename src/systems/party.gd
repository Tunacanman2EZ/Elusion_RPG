# party.gd - the party you are in, as the server last said (0.42.0).
#
# The owner: "we need to be able to start parties so we need a tab for
# parties", and of what a party does: its members in the Party window (Social
# > Party, partypanel.gd), "Party chat" (the chat window's Party tab) and
# "Party on the map" (mapscreen.gd). The server keeps the party (app.py,
# PARTIES); the broadcast poll carries who is in yours every ten seconds
# (`party`: id, leader, members), and the Party window's own reads refresh it
# sooner. Everything that colours a name or draws a member reads it here.
#
# STATIC, AND PER LOGIN: every area has its own HUD and its own players, and
# the party is the account's, not the scene's. `kept_for` says whose it is, so
# logging in as somebody else never shows the last account's party.
class_name Party
extends RefCounted

# Your party's names, over their heads, on the map and in the Party window.
const COLOUR := Color(0.45, 0.85, 1.0)

static var id: int = 0
static var leader: String = ""
static var members: Array[String] = []
# Moves on every change, so something drawn from it knows to redraw.
static var revision: int = 0
static var kept_for: String = ""


static func apply(data: Variant, username: String = "") -> bool:
	"""Take the server's word on the party - the poll's {"id", "leader",
	"members": [names]}, or a Party window's whole answer. True if it changed."""
	var who: String = username if username != "" else Api.username
	var new_id: int = 0
	var new_leader: String = ""
	var new_members: Array[String] = []
	if data is Dictionary:
		new_id = int(data.get("id", 0))
		new_leader = str(data.get("leader", ""))
		var listed: Variant = data.get("members", [])
		if listed is Array:
			for one in listed:
				if one is Dictionary:
					new_members.append(str(one.get("username", "")))
				elif one is String:
					new_members.append(one)
	if new_id <= 0:
		new_id = 0
		new_leader = ""
		new_members = []
	if new_id == id and new_leader == leader and new_members == members and who == kept_for:
		return false
	id = new_id
	leader = new_leader
	members = new_members
	kept_for = who
	revision += 1
	return true


static func forget() -> void:
	apply(null, "")


static func in_one() -> bool:
	return id != 0 and kept_for == Api.username


static func is_member(username: String) -> bool:
	"""Whether `username` is in your party - never yourself's question."""
	if not in_one() or username == "":
		return false
	# Account names are unique ignoring case, as the server compares them.
	var wanted: String = username.to_lower()
	for one in members:
		if one.to_lower() == wanted:
			return true
	return false


static func is_leader() -> bool:
	return in_one() and leader == Api.username
