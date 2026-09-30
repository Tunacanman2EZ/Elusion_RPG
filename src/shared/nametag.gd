# nametag.gd — how a player's name is drawn anywhere but over their head:
# in the colour THEY chose, with a mark for their rank.
#
# COLOUR IS YOURS, RANK IS A BADGE. Names used to be painted by rank - owner
# gold, dev blue, mod green, everyone else parchment - and the colour a player
# picked in Options was drawn over their own head and nowhere else. For staff
# the slider did nothing at all. Now the server stores the hue each player
# chose (users.name_hue) and sends it with every name, and rank is shown by
# something a player cannot pick: the owner's crown, and a small MOD or DEV.
#
# WHY A BADGE AND NOT A COLOUR. The moment colours are free, a colour cannot
# prove anything - a player can choose the owner's gold. A badge drawn from the
# `role` the server sends cannot be chosen, so it is the one thing on a name
# that still has to be true.
#
# NO class_name, ON PURPOSE. A new class_name is invisible until the editor
# rescans (see CLAUDE.md), and every panel that draws a name would stop
# compiling on a fresh checkout until somebody opened the editor. Each caller
# preloads this file instead:  const NameTag := preload("res://src/shared/nametag.gd")
extends RefCounted


# The owner's crown - the same art over their head, in chat and in every list.
const CROWN_PATH := "res://art/enemy/behemothcrown.png"
const CROWN_SIZE := Vector2(26, 15)
const CROWN_RANK := "owner"

# The ranks that wear a word, and the word. The owner wears the crown instead;
# a player wears nothing, which is what makes the other three stand out.
const BADGES := {"mod": "MOD", "dev": "DEV"}
const BADGE_FONT_SIZE := 9


static func colour(hue: Variant) -> Color:
	"""The colour a name is drawn in, from the hue the server sent.

	NULL MEANS "NEVER CHOSE", and gets the default from Settings - the one place
	the default lives. Anything that is not a hue on the wheel is treated the
	same way rather than trusted: this is a number off the wire.
	"""
	if (hue is int or hue is float) and float(hue) >= 0.0 and float(hue) < 360.0:
		return Settings.name_colour(float(hue))
	return Settings.name_colour(float(Settings.DEFAULTS["name_hue"]))


static func badge(role: String) -> String:
	return str(BADGES.get(role, ""))


static func badge_colour(role: String) -> Color:
	# THE RANK COLOURS STILL MEAN RANK - they colour the badge now, not the name.
	return Api.colour_for_role(role)


static func wears_crown(role: String) -> bool:
	return role == CROWN_RANK


static func bbcode(escaped_name: String, role: String, hue: Variant) -> String:
	"""The name for a RichTextLabel: crown or badge, then the name in its colour.

	TAKES THE NAME ALREADY ESCAPED. Chat owns its escaping - see _escape() in
	chatpanel.gd - and a second, different escape in here would be two opinions
	about what a bracket is.
	"""
	return bbcode_mark(role) + bbcode_name(escaped_name, hue)


static func bbcode_mark(role: String) -> String:
	"""Just the crown or the badge, with its trailing space - "" for a player.

	Separate from the name so chat can put the guild tag between them: crown,
	guild, name, which is the order chat has always used.
	"""
	if wears_crown(role):
		# AT THE ART'S OWN 26x15. RichTextLabel scales an [img] to whatever it
		# is given, and anything else turns 26 columns of pixel art into a smear.
		return "[img=%dx%d]%s[/img] " % [int(CROWN_SIZE.x), int(CROWN_SIZE.y), CROWN_PATH]
	if badge(role) != "":
		return "[color=#%s][font_size=%d]%s[/font_size][/color] " % [
			badge_colour(role).to_html(false), BADGE_FONT_SIZE + 1, badge(role)]
	return ""


static func bbcode_name(escaped_name: String, hue: Variant) -> String:
	return "[color=#%s]%s[/color]" % [colour(hue).to_html(false), escaped_name]


static func add_to(line: Container, text: String, role: String, hue: Variant,
		font_size: int = 12) -> Label:
	"""Crown or badge, then the name, into a row. Returns the name's Label.

	THE MARK GOES BEFORE THE NAME, where chat puts it, so the lists and the
	chat log read the same way round.
	"""
	if wears_crown(role):
		var crown := TextureRect.new()
		crown.name = "crown"
		crown.texture = load(CROWN_PATH) as Texture2D
		# EXPAND_IGNORE_SIZE or custom_minimum_size is only a floor and the art
		# sets the real width - the trap the board header and the inventory icon
		# both hit. With it, 26x15 is exactly 26x15.
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.custom_minimum_size = CROWN_SIZE
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crown.tooltip_text = "Owner"
		crown.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(crown)
	elif badge(role) != "":
		line.add_child(badge_label(role))

	var name_label := Label.new()
	name_label.name = "name"
	name_label.text = text
	name_label.add_theme_color_override("font_color", colour(hue))
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name_label)
	return name_label


static func badge_label(role: String) -> Label:
	var label := Label.new()
	label.name = "badge"
	label.text = badge(role)
	label.add_theme_color_override("font_color", badge_colour(role))
	label.add_theme_font_size_override("font_size", BADGE_FONT_SIZE)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.tooltip_text = "Moderator" if role == "mod" else "Developer"
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label
