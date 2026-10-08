# creditsscreen.gd - the Credits window: who made what, and who helped (0.11.1).
#
# The owner, 7 Oct: "as for credits i think we should make it a button in
# settings that says credits we can separate artists audio and support
# there". Options > Credits.
#
# FOUR TABS:
#   Art      the artists, and the typefaces the game offers
#   Audio    the sounds, and who recorded them
#   Support  everyone who bought a hot cocoa - SUPPORTERS below
#   Engine   Godot, and the parts of it whose licences ask to be shown
#
# THE CREDITS USED TO BE THE LAST PAGE OF THE FIELD'S WELCOME (field.gd), read
# once a login on the way through the portal and never again. They live here
# now, where anyone can find them, and the welcome is free to tell the story.
#
# THE ENGINE TAB IS NOT DECORATION. Godot is MIT-licensed, and the MIT licence
# asks for its notice to travel with every copy - for a game, the credits
# screen. So do FreeType, which draws every letter, ENet, and Mbed TLS, which
# carries every https request and the presence socket. The text is read from
# the engine itself (Engine.get_license_text(), get_copyright_info(),
# get_license_info()), so an engine upgrade brings its own notices with it.
extends Control
class_name CreditsScreen


signal closed()


enum Tab { ART, AUDIO, SUPPORT, ENGINE }

# =============================================================================
# SUPPORTERS - THE ONE LIST YOU EDIT
# =============================================================================
# Everyone who bought a hot cocoa (elusionrpg.com/contribute.html) and put
# their name in the PayPal note. This is the only list of them: the website
# keeps none, and sends people here. The name exactly as they want it shown,
# newest LAST; the window shows them in this order.
#
#     const SUPPORTERS: Array[String] = ["Ada L.", "Jordan"]
const SUPPORTERS: Array[String] = []

const SUPPORT_PAGE := "https://elusionrpg.com/contribute.html"

# =============================================================================
# THE ART AND THE SOUND
# =============================================================================
# Each entry: who, a link to their own page (or ""), and what they made.
const ART := [
	{"name": "Ahvassa", "link": "https://ahvassa.itch.io/",
		"made": "Every character, monster and pet, the towns, fields, tiles and buildings, the portals, and the mythic weapons - drawn for Elusion."},
	{"name": "Caio Carlos - Clockwork Raven Studios", "link": "https://www.clockworkravenstudios.com/",
		"made": "The items and icons: weapons, armour, rings and amulets, potions, coins and fishing gear, from their pixel art asset pack."},
]

const AUDIO := [
	{"name": "Robert - Elusion Studios", "link": "",
		"made": "Every sound in the game, recorded on his own instruments: the portal is a Stylophone played through a Stylophone CPM DS-2, and the fire pit was made in REAPER."},
]

# THE TYPEFACES Options > Font offers, and the emoji in chat. Every one is
# under the SIL Open Font License 1.1, and its OFL.txt ships beside it
# (assetlicense.md). Keyed by the file, so the suite can hold this list to
# Settings.FONT_STYLES: a font added there and not here fails.
const FONTS := [
	{"file": "res://assets/stylefonts/pixelifysans/PixelifySans.ttf", "name": "Pixelify Sans",
		"by": "Copyright 2021 The Pixelify Sans Project Authors"},
	{"file": "res://assets/stylefonts/tiny5/Tiny5-Regular.ttf", "name": "Tiny5",
		"by": "Copyright 2022-2024 The Tiny5 Project Authors"},
	{"file": "res://assets/stylefonts/medievalsharp/MedievalSharp.ttf", "name": "MedievalSharp",
		"by": "Copyright 2011 wmk69 (Wojciech Kalinowski)"},
	{"file": "res://assets/stylefonts/imfellenglish/IMFeENrm28P.ttf", "name": "IM FELL English",
		"by": "Copyright 2007/2010 Igino Marini"},
	{"file": "res://assets/stylefonts/grenzegotisch/GrenzeGotisch.ttf", "name": "Grenze Gotisch",
		"by": "Copyright 2020 The Grenze Gotisch Project Authors"},
	{"file": "res://assets/fonts/NotoColorEmoji.ttf", "name": "Noto Color Emoji",
		"by": "Copyright 2022 Google Inc."},
]
const FONT_LICENCE := "SIL Open Font License 1.1 - each font's licence text ships with it."

# THE PARTS OF GODOT whose licences ask to be shown in the game itself - the
# three Godot's own guide to complying with licences names. Matched against
# Engine.get_copyright_info()'s names.
const ENGINE_NOTICES := ["The FreeType Project", "ENet", "Mbed TLS"]
const GODOT_LINK := "https://godotengine.org"

const HEADING_COLOUR := Color(0.95, 0.85, 0.6)
const NAME_COLOUR := Color(0.95, 0.92, 0.84)
const TEXT_COLOUR := Color(0.78, 0.75, 0.68)
const QUIET_COLOUR := Color(0.6, 0.57, 0.52)
const LINK_COLOUR := Color(0.55, 0.8, 1.0)

@onready var close_button: Button = get_node_or_null("%closebutton")
@onready var art_button: Button = get_node_or_null("%artbutton")
@onready var audio_button: Button = get_node_or_null("%audiobutton")
@onready var support_button: Button = get_node_or_null("%supportbutton")
@onready var engine_button: Button = get_node_or_null("%enginebutton")
@onready var list: VBoxContainer = get_node_or_null("%list")
@onready var list_scroll: ScrollContainer = get_node_or_null("%listscroll")

var tab: int = Tab.ART
# The names the Support tab shows: SUPPORTERS, held here so the suite can show
# the tab with names in it while the real list is still empty.
var supporters: Array[String] = SUPPORTERS.duplicate()
var _window: PanelWindow
# EACH TAB IS BUILT ONCE, the first time it is shown, into a box of its own
# under `list`, and after that only shown or hidden. The Engine tab is several
# licences long - about a fifth of a second to lay out - and switching back to
# it should not pay that again.
var _pages: Dictionary = {}   # Tab -> VBoxContainer
var _page: VBoxContainer = null


func _ready() -> void:
	_window = PanelWindow.attach(self, "credits")
	if close_button != null:
		close_button.pressed.connect(close)
	var group := ButtonGroup.new()
	var buttons: Array = [art_button, audio_button, support_button, engine_button]
	for i in buttons.size():
		var button: Button = buttons[i]
		if button != null:
			button.button_group = group
			button.pressed.connect(show_tab.bind(i))
	visible = false


# =============================================================================
# OPENING AND CLOSING
# =============================================================================

func open() -> void:
	visible = true
	show_tab(tab)


func close() -> void:
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func show_tab(which: int) -> void:
	tab = which
	var buttons: Array = [art_button, audio_button, support_button, engine_button]
	for i in buttons.size():
		if buttons[i] != null:
			(buttons[i] as Button).set_pressed_no_signal(i == which)
	if list == null:
		return
	if not _pages.has(which):
		_page = VBoxContainer.new()
		_page.name = "page%d" % which
		_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_page.add_theme_constant_override("separation", 10)
		list.add_child(_page)
		_pages[which] = _page
		match which:
			Tab.ART:
				_fill_art()
			Tab.AUDIO:
				_fill_people(AUDIO)
				_add_text("More sound is on its way, recorded the same way, one at a time.", QUIET_COLOUR, 12)
			Tab.SUPPORT:
				_fill_support()
			Tab.ENGINE:
				_fill_engine()
	for key in _pages:
		(_pages[key] as Control).visible = key == which
	_page = _pages[which]
	if list_scroll != null:
		list_scroll.scroll_vertical = 0


func page() -> VBoxContainer:
	"""The box the tab on show is drawn in."""
	return _pages.get(tab, null)


# =============================================================================
# THE TABS
# =============================================================================

func _fill_art() -> void:
	_fill_people(ART)
	_add_heading("Fonts")
	for font in FONTS:
		_add_person(str(font["name"]), "", str(font["by"]))
	_add_text(FONT_LICENCE, QUIET_COLOUR, 12)


func _fill_people(people: Array) -> void:
	for person in people:
		_add_person(str(person["name"]), str(person["link"]), str(person["made"]))


func _fill_support() -> void:
	_add_text(support_intro(supporters), TEXT_COLOUR, 13)
	for supporter in supporters:
		_add_text(supporter, NAME_COLOUR, 15).set_meta("supporter", true)
	_add_link("Buy a hot cocoa - elusionrpg.com", SUPPORT_PAGE)


static func support_intro(names: Array) -> String:
	"""What the Support tab says above the names: thanks when there are some,
	an invitation when there are none yet."""
	if names.is_empty():
		return "Elusion is free to play. Buy the developer a hot cocoa - any amount - with your name in the PayPal note, and your name goes here, the first on the list."
	return "Elusion is free to play. These people bought the developer a hot cocoa anyway. Thank you."


func _fill_engine() -> void:
	_add_heading("Made with Godot Engine")
	_add_link("godotengine.org", GODOT_LINK)
	_add_text(reflow(Engine.get_license_text()), TEXT_COLOUR, 11)
	var licences: Dictionary = Engine.get_license_info()
	for part in engine_notices():
		_add_heading(str(part["name"]))
		_add_text(str(part["copyright"]), NAME_COLOUR, 12)
		if str(part["name"]) == "The FreeType Project":
			# The FreeType licence asks for this sentence in the credits, in
			# these words.
			_add_text("Portions of this software are copyright © %s The FreeType Project (www.freetype.org). All rights reserved." % str(part["years"]),
				TEXT_COLOUR, 11)
		_add_text(reflow(str(licences.get(str(part["licence"]), "Licence: %s" % part["licence"]))), QUIET_COLOUR, 10)
	_add_heading("Everything else Godot is built from")
	_add_text(engine_components_text(), QUIET_COLOUR, 10)


static func reflow(text: String) -> String:
	"""A licence as its paragraphs. The texts come broken at 80 columns for a
	terminal, and a label that wraps them again leaves a word or two stranded
	on every other line; a blank line is still a new paragraph."""
	var paragraphs := PackedStringArray()
	for paragraph in text.replace("\r\n", "\n").split("\n\n"):
		var words := PackedStringArray()
		for line in paragraph.split("\n"):
			if line.strip_edges() != "":
				words.append(line.strip_edges())
		if not words.is_empty():
			paragraphs.append(" ".join(words))
	return "\n\n".join(paragraphs)


static func engine_notices() -> Array:
	"""[{name, copyright, years, licence}] for each part named in ENGINE_NOTICES
	that this build of Godot carries, read from the engine."""
	var out: Array = []
	for component in Engine.get_copyright_info():
		var part_name: String = str(component.get("name", ""))
		if not ENGINE_NOTICES.has(part_name):
			continue
		for part in component.get("parts", []):
			var lines: Array = part.get("copyright", [])
			var first: String = str(lines[0]) if not lines.is_empty() else ""
			out.append({"name": part_name, "copyright": "Copyright " + ", ".join(lines),
				"years": first.get_slice(",", 0).strip_edges(), "licence": str(part.get("license", ""))})
	return out


static func engine_components_text() -> String:
	"""One line per third-party part of Godot: its name, who holds it, and
	under what licence."""
	var lines := PackedStringArray()
	for component in Engine.get_copyright_info():
		for part in component.get("parts", []):
			lines.append("%s - %s (%s)" % [str(component.get("name", "")),
				"; ".join(part.get("copyright", [])), str(part.get("license", ""))])
	return "\n".join(lines)


# =============================================================================
# ROWS
# =============================================================================

func _add_heading(text: String) -> Label:
	var label := _add_text(text, HEADING_COLOUR, 15)
	label.name = "heading"
	return label


func _add_person(who: String, link: String, made: String) -> void:
	var box := VBoxContainer.new()
	box.name = "person"
	box.add_theme_constant_override("separation", 0)
	if link != "":
		var button := LinkButton.new()
		button.name = "name"
		button.text = who
		button.uri = link
		button.tooltip_text = link
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_color_override("font_color", LINK_COLOUR)
		button.add_theme_font_size_override("font_size", 15)
		box.add_child(button)
	else:
		var label := Label.new()
		label.name = "name"
		label.text = who
		label.add_theme_color_override("font_color", NAME_COLOUR)
		label.add_theme_font_size_override("font_size", 15)
		box.add_child(label)
	var detail := Label.new()
	detail.name = "made"
	detail.text = made
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_color_override("font_color", TEXT_COLOUR)
	detail.add_theme_font_size_override("font_size", 12)
	box.add_child(detail)
	_page.add_child(box)


func _add_text(text: String, colour: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", font_size)
	_page.add_child(label)
	return label


func _add_link(text: String, uri: String) -> LinkButton:
	var button := LinkButton.new()
	button.name = "link"
	button.text = text
	button.uri = uri
	button.tooltip_text = uri
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", LINK_COLOUR)
	button.add_theme_font_size_override("font_size", 13)
	_page.add_child(button)
	return button
