# minigamescard.gd - the Minigames button's card: each minigame, your wait,
# and Go (0.93.3).
#
# The owner: "we need to get rid of ladder and make this a button in hud that
# says minigames this dungeon will have a 1 day wait timer for players", and
# the day starts when you press Go. So the town square's ladder down to the
# Endless is gone, and the bar's Minigames button opens this card above it:
#
#   The Endless
#   A horde that never stops. Once a day.
#   Ready  /  Back in 13h 20m  /  You are in it
#                                        [ Go ]  /  [ Leave ]
#
# THE WAIT IS THE SERVER'S (the API's minigames/): opening the card asks how
# long is left (GET /api/minigames), and Go asks first (POST
# /api/minigames/enter) - let in, it takes you to the Endless's corridor; a 409
# says how long is left, in the server's own words. Per account; the owner
# skips it. A party's members each press Go and land in the party's arena.
#
# AND THE WAY OUT. The Endless's door lets you in and not back (cryptdoor.gd
# one_way(), the owner: "the door needs to be 1 way entry also"), so inside the
# Endless the card's button is Leave, to town - from the arena as from the
# corridor, whose ladder still goes up. With loot in the chest (0.93.4) Leave
# asks twice: the chest waits on the server, and the next Go empties it.
#
# THE HEALER'S RUN (0.98.0, healerrun.gd) is the card's second minigame: a
# shooter with the healer as the ship, played over the screen from town (Go
# elsewhere says "Play it from town."). Since 0.99.0 everyone's, three runs a
# day: Go asks the server (POST /api/minigames/enter, with the character's
# slot) and opens the run with its id and what it pays; the listing says how
# many runs are left today, or when the next one is.
#
# THE MAGE'S STAND (0.107.0, magestand.gd) is the third, the owner's alone
# while it is built (`shows_mage_stand`): Go, in town, opens it - it pays
# nothing, so nothing is asked of the server.
#
# THE DESCENT (0.112.0, descentrun.gd) is the fourth, the owner's alone while
# it is built (`shows_descent`): THE WARRIOR'S (the owner: "this will be the
# warriors decent", as the Healer's Run is the healer's and the Stand the
# mage's), a roguelike run down a crypt as your own warrior. Go, playing a
# warrior (`class_now`), travels there (its own area, as the Endless is) and
# asks the server nothing - step 1 pays nothing; inside it, the row's button
# is Leave, to town.
#
# THE FORGE (forgerun.gd) is the fifth, the owner's alone while it is built
# (`shows_forge`): THE TANK'S WORLD - an island in a lake of lava that floods
# slice by slice - but open to every class (the owner: "open to any class but
# the tank benefits the most"). Go asks the server first since 0.120.0 -
# once a day, as the Endless, and the status says your best time - then
# travels there (its own area, as the Descent is); inside it, the row's button
# is Leave, to town, asked twice while the chest holds loot.
#
# CUT THE CLOTH (0.130.0, clothrun.gd) is the sixth, the owner's alone while
# it is built (`shows_cloth`): the old map's slime plague cut away piece by
# piece, played over the screen from town like the Stand. Since 0.131.0 three
# runs a day, as the Healer's Run: Go asks the server (POST /api/minigames/enter, game
# "cloth") and opens the run with its id and what it pays; the listing says
# how many runs are left today, or when the next one is. Any class.
#
# WITH THE PARTY (0.105.0): in a party, with a server that seats the run a
# room per party (`healer_party`), Go opens the run's start panel without
# asking (`open_lobby`): the run of the day is asked for when everyone is
# ready and the count starts, so leaving while somebody is away costs nothing.
#
# A TILE A GAME (0.119.1). The owner, of the card grown to five games: "need
# image 1 upgraded", and of the mock-up, "looks great". Each game is a tile
# (`_tile()`): a portrait from the game's own art (PORTRAITS - a frame of the
# class or monster it is about, cropped to the figure, `portrait_of()`), the
# name with small tags (DAILY, 3 A DAY, TESTING, the class) where sentences
# said it, one line, the status and Go. About 400 px tall where the rows were
# 640. Every member the rest of this file paints (`healer_box`, `forge_go`
# ...) is the same node it was, inside its tile.
#
# Built by the HUD (attach()), no class_name, so a fresh checkout needs no
# editor rescan.
extends PanelContainer

const COLOUR := Color(1.0, 0.86, 0.5)
const COLOUR_HINT := Color(0.82, 0.78, 0.7)
const COLOUR_READY := Color(0.6, 0.9, 0.55)
const COLOUR_WAIT := Color(1.0, 0.72, 0.4)
const FONT_SIZE := 14
const WIDTH := 430.0
const GAP := 6.0
const STATUS_WIDTH := 230.0
const GAME := "endless"
const ENTRANCE := "endless_entrance"
const TOWN := "elusion"
const BLURB := "A horde that never stops."
const UNREACHABLE := "Could not reach the server - try again."
const HEALER_BLURB := "Up a crypt path, shooting - up to 20,000 gold a run."
const HEALER_GAME := "healerrun"
const FROM_TOWN := "Play it from town."
const STAND_BLURB := "Rain meteors on the horde at the gate."
const DESCENT_BLURB := "Down a crypt room by room - doors, upgrades, keepers."
# EVERY CLASS (0.124.0, the owner: "any class can join but we have to set up
# bonuses for all 4 chars"): it was the warrior's alone (DESCENT_CLASS); the
# warrior's story is still told to a warrior only (descentrun.gd).
const DESCENT_CLASS := "warrior"
const DESCENT := "descent"
const DESCENT_ENTRANCE := "descent_entrance"
const FORGE_BLURB := "Hold the anvil while the lava floods the island."
const FORGE := "forge"
const FORGE_ENTRANCE := "forge_entrance"
const CLOTH_BLURB := "Cut the old map away from the slimes, piece by piece."
const CLOTH_GAME := "cloth"
# THE TILES (0.119.1): each game's portrait (a scene whose sprite is the
# picture), its rim, and its tags - [words, colour, what it means].
const PORTRAITS := {
	"endless": ["res://scene/enemy/poisonslime.tscn", Color(0.55, 0.85, 0.35)],
	"healerrun": ["res://scene/characters/healer.tscn", Color(0.45, 0.9, 0.6)],
	"magestand": ["res://scene/characters/mage.tscn", Color(0.45, 0.65, 1.0)],
	"descent": ["res://scene/characters/warrior.tscn", Color(0.95, 0.4, 0.35)],
	"forge": ["res://scene/characters/tank.tscn", Color(1.0, 0.6, 0.25)],
	"cloth": ["res://scene/projectiles/turretprojectile.tscn", Color(0.86, 0.77, 0.61)],
}
const TAG_DAILY := ["DAILY", Color(0.35, 0.3, 0.6), "Once a day"]
const TAG_THREE := ["3 A DAY", Color(0.35, 0.3, 0.6), "Three runs a day"]
const TAG_TESTING := ["TESTING", Color(0.55, 0.35, 0.1), "Yours only while it is built"]
const TAG_TEXT := Color(1.0, 0.95, 0.85)
const TILE_BG := Color(0.09, 0.07, 0.05, 0.92)
const PORTRAIT_SIZE := 48.0

# The suite's doors: the two requests, where Go and Leave travel to, and which
# area this game is in.
var list_request: Callable = Callable(Api, "get_json")
var enter_request: Callable = Callable(Api, "post")
var travel: Callable = Callable(self, "_travel")
var area_now: Callable = Callable(AreaRegistry, "current_area_id")
# How many cells of the Endless's chest hold something (0.93.4): the chest in
# the corridor's own count (endlesschest.gd `used`). A seam for the suite.
var chest_count: Callable = Callable(self, "_chest_count")
# The Healer's Run's doors: who sees it (the owner, in step 1) and what Go does.
var shows_healer_run: Callable = Callable(self, "_shows_healer_run")
var open_run: Callable = Callable(self, "_open_run")
var healer_party: Callable = Callable(self, "_healer_party")
var open_lobby: Callable = Callable(self, "_open_lobby")
# The Mage's Stand's doors: who sees it (the owner, while it is built) and Go.
var shows_mage_stand: Callable = Callable(self, "_shows_mage_stand")
var open_stand: Callable = Callable(self, "_open_stand")
# The Descent's: who sees it (the owner, while it is built), and the class
# being played - it is the warrior's.
var shows_descent: Callable = Callable(self, "_shows_descent")
var class_now: Callable = Callable(CharacterData, "active_class_id")
# The Forge's: who sees it (the owner, while it is built).
var shows_forge: Callable = Callable(self, "_shows_forge")
# Cut the Cloth's: who sees it (the owner, while it is built) and Go.
var shows_cloth: Callable = Callable(self, "_shows_cloth")
var open_cloth: Callable = Callable(self, "_open_cloth")

var hud: Node = null
var title: Label = null
var game_name: Label = null
var blurb: Label = null
var endless_box: PanelContainer = null
var status: Label = null
var go_button: Button = null
var close_button: Button = null
var healer_box: PanelContainer = null
var healer_status: Label = null
var healer_go: Button = null
var stand_box: PanelContainer = null
var stand_status: Label = null
var stand_go: Button = null
var descent_box: PanelContainer = null
var descent_status: Label = null
var descent_go: Button = null
var forge_box: PanelContainer = null
var forge_status: Label = null
var forge_go: Button = null
var cloth_box: PanelContainer = null
var cloth_status: Label = null
var cloth_go: Button = null
# Cut the Cloth's runs left today and the wait when none are, as the server
# said and when.
var cloth_left: int = 3
var cloth_wait: int = 0
var _cloth_known: bool = false
var _cloth_said_msec: int = 0
var _cloth_busy: bool = false
var _cloth_said: String = ""
# The Healer's Run's runs left today, and the wait when none are, as the
# server said and when.
var healer_left: int = 3
var healer_wait: int = 0
var _healer_known: bool = false
var _healer_said_msec: int = 0
var _healer_busy: bool = false
var _healer_said: String = ""
# Seconds of the wait left when the server last said, and when that was.
var ready_in: int = 0
var _said_at_msec: int = 0
var _known: bool = false
var _busy: bool = false
# The server did not answer (the listing or Go): said until it does, and Go
# may be pressed - the server decides at Go anyway.
var _failed: bool = false
# LEAVE WITH LOOT IN THE CHEST ASKS TWICE (0.93.4): the chest waits on the
# server until the next Go - which empties it - so leaving it is losing it.
# The first press says so; the second leaves. Opening the card again forgets.
var _leave_armed: bool = false
# THE FORGE'S DAY AND BEST (0.120.0), as the server last said them.
var forge_wait: int = 0
var forge_best: int = 0
var _forge_known: bool = false
var _forge_said_msec: int = 0
var _forge_busy: bool = false
var _forge_failed: bool = false
var _forge_leave_armed: bool = false

# A RUN TO PLAY LIGHTS THE BAR'S BUTTON (0.113.0; since 0.113.1 until you go
# in, not until the card is opened - the owner: "green vanished after i
# clicked on"). PER LOGIN, NOT PER CARD: every area has its own HUD and card,
# and the bar's dot must not go out at a door. Static, and forgotten when
# another account is playing.
#
# game id -> the unix second it is (or was) ready; a game not in it is unknown.
static var _ready_at: Dictionary = {}
static var _news_by: String = ""
# The account whose listing has been asked for at this login.
static var _asked_by: String = ""
# How often the card looks at the clock for a wait just ended.
const NEWS_SECONDS := 5.0


static func attach(on_hud: Node) -> Control:
	var card: Control = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).new()
	card.name = "minigamescard"
	card.set("hud", on_hud)
	on_hud.add_child(card)
	return card


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	title = _label("title", "Minigames", 16, COLOUR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	close_button = Button.new()
	close_button.name = "close"
	close_button.text = "×"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	var endless: Array = _tile(column, "endless", "The Endless", BLURB, [TAG_DAILY])
	endless_box = endless[0]
	game_name = endless[1]
	blurb = endless[2]
	status = endless[3]
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go_button = _go_button("go", _on_go)
	(endless[4] as HBoxContainer).add_child(go_button)
	var healer: Array = _tile(column, "healerrun", "The Healer's Run", HEALER_BLURB,
		[TAG_THREE, ["HEALER", Color(0.2, 0.45, 0.3), "The healer's"]])
	healer_box = healer[0]
	healer_status = healer[3]
	healer_go = _go_button("healergo", _on_healer_go)
	(healer[4] as HBoxContainer).add_child(healer_go)
	var stand: Array = _tile(column, "magestand", "The Mage's Stand", STAND_BLURB,
		[TAG_TESTING, ["MAGE", Color(0.2, 0.3, 0.55), "The mage's"]])
	stand_box = stand[0]
	stand_status = stand[3]
	stand_go = _go_button("standgo", _on_stand_go)
	(stand[4] as HBoxContainer).add_child(stand_go)
	var descent: Array = _tile(column, "descent", "The Descent", DESCENT_BLURB,
		[TAG_TESTING, ["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go - each with its own upgrades"]])
	descent_box = descent[0]
	descent_status = descent[3]
	descent_go = _go_button("descentgo", _on_descent_go)
	(descent[4] as HBoxContainer).add_child(descent_go)
	var forge: Array = _tile(column, "forge", "The Forge", FORGE_BLURB,
		[TAG_DAILY, TAG_TESTING, ["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go"],
		["TANK BEST", Color(0.55, 0.3, 0.12), "The tank's world - he lasts longest"]])
	forge_box = forge[0]
	forge_status = forge[3]
	forge_go = _go_button("forgego", _on_forge_go)
	(forge[4] as HBoxContainer).add_child(forge_go)
	var cloth: Array = _tile(column, "cloth", "Cut the Cloth", CLOTH_BLURB,
		[TAG_THREE, TAG_TESTING, ["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go"]])
	cloth_box = cloth[0]
	cloth_status = cloth[3]
	cloth_go = _go_button("clothgo", _on_cloth_go)
	(cloth[4] as HBoxContainer).add_child(cloth_go)


func _tile(column: Control, id: String, game_title: String, line: String, tags: Array) -> Array:
	"""A game's tile in `column`: [tile, its name, its line, its status, the
	row its Go goes in]."""
	var tile := PanelContainer.new()
	tile.name = id
	tile.add_theme_stylebox_override("panel", _flat(TILE_BG, Color(COLOUR, 0.28), 4, 6, 1))
	column.add_child(tile)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tile.add_child(row)
	var art: Array = PORTRAITS.get(id, ["", COLOUR_HINT])
	var frame := PanelContainer.new()
	frame.name = id + "portrait"
	frame.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", _flat(Color(0.05, 0.04, 0.04, 0.95), art[1], 4, 2, 2))
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(PORTRAIT_SIZE - 4.0, PORTRAIT_SIZE - 4.0)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = portrait_of(str(art[0]))
	frame.add_child(pic)
	row.add_child(frame)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 1)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	words.add_child(head)
	var name_label: Label = _label(id + "game", game_title, FONT_SIZE, COLOUR)
	head.add_child(name_label)
	for tag in tags:
		head.add_child(_tag(tag))
	var line_label: Label = _label(id + "blurb", line, 11, COLOUR_HINT)
	words.add_child(line_label)
	var state: Label = _label(id + "status", "", 12, COLOUR_HINT)
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	words.add_child(state)
	return [tile, name_label, line_label, state, row]


func _go_button(id: String, on_press: Callable) -> Button:
	var go := Button.new()
	go.name = id
	go.text = "Go"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(64, 30)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(on_press)
	return go


func _tag(tag: Array) -> Control:
	"""A small coloured pill: DAILY, TESTING, the class."""
	var pill := PanelContainer.new()
	var style: StyleBoxFlat = _flat(tag[1], (tag[1] as Color).lightened(0.35), 3, 0, 1)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.tooltip_text = str(tag[2])
	pill.add_child(_label("tag", str(tag[0]), 9, TAG_TEXT))
	return pill


static func _flat(bg: Color, border: Color, radius: int, margin: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style


# A portrait a scene, cropped once a run (the card is built again in every area).
static var _portraits: Dictionary = {}


static func portrait_of(scene_path: String) -> Texture2D:
	"""The first frame of the scene's sprite facing down, cropped to the figure -
	read off the scene's state, never instanced. A sprite with no facings (the
	healer's shot, Cut the Cloth's) gives its first animation's first frame."""
	if _portraits.has(scene_path):
		return _portraits[scene_path]
	var picture: Texture2D = null
	var packed: PackedScene = load(scene_path) as PackedScene if scene_path != "" and ResourceLoader.exists(scene_path) else null
	if packed != null:
		var state: SceneState = packed.get_state()
		for n in state.get_node_count():
			for p in state.get_node_property_count(n):
				if state.get_node_property_name(n, p) != &"sprite_frames":
					continue
				var frames: SpriteFrames = state.get_node_property_value(n, p) as SpriteFrames
				if frames == null:
					continue
				var anims: Array = ["idledown", "walkdown", "attackdown"]
				if not anims.any(func(a: String) -> bool: return frames.has_animation(a)) and frames.get_animation_names().size() > 0:
					anims = [str(frames.get_animation_names()[0])]
				for anim in anims:
					if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
						var image: Image = frames.get_frame_texture(anim, 0).get_image()
						if image != null and not image.is_empty():
							if image.is_compressed():
								image.decompress()
							picture = ImageTexture.create_from_image(image.get_region(image.get_used_rect()))
						break
				if picture != null:
					break
			if picture != null:
				break
	_portraits[scene_path] = picture
	return picture

func _label(id: String, text: String, font_px: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", colour)
	return label


func _ready() -> void:
	# THE BAR'S LOOK: its theme and panel, as the trade card takes them.
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	if nav != null:
		theme = nav.theme
		var style: StyleBox = nav.get_theme_stylebox("panel")
		if style != null:
			add_theme_stylebox_override("panel", style)
	var clock := Timer.new()
	clock.name = "newsclock"
	clock.wait_time = NEWS_SECONDS
	clock.autostart = true
	clock.timeout.connect(paint_news)
	add_child(clock)
	_forget_news_if_another()
	paint_news()
	# ONCE A LOGIN, the listing, so the button knows a wait without the card
	# being opened. Opening the card asks again anyway.
	if Api.is_logged_in() and _asked_by != Api.username and not inside_endless():
		_ask_for_news.call_deferred()


func _ask_for_news() -> void:
	_asked_by = Api.username
	var res: Dictionary = await list_request.call("/api/minigames", 6.0)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not res.get("ok", false):
		_asked_by = ""
		return
	if not visible:
		take_listing(res)


# =============================================================================
# A RUN TO PLAY (0.113.0, 0.113.1)
# =============================================================================
# Lit while a run is yours to play, out from the moment you go in, and lit
# again when the server's wait is over. THE SERVER COUNTS EACH ENTRY, per
# account (the API's minigames/); the owner skips every wait there, so his
# button is lit whenever he is out of a run.

static func forget_news() -> void:
	"""Nothing known of any game: the suite's way back to a fresh login."""
	_ready_at.clear()
	_asked_by = ""
	_news_by = Api.username


static func _forget_news_if_another() -> void:
	if _news_by != Api.username:
		_ready_at.clear()
		_asked_by = ""
		_news_by = Api.username


static func note_wait(game: String, seconds: int) -> void:
	"""What the server said of a game: ready now (0), or in `seconds`."""
	_forget_news_if_another()
	var now: int = int(Time.get_unix_time_from_system())
	if seconds > 0:
		_ready_at[game] = now + seconds
	elif int(_ready_at.get(game, now + 1)) > now:
		_ready_at[game] = now


static func forget_wait(game: String) -> void:
	"""A run was just begun: the button goes out, and its next wait is the
	server's to say, so the next area's card asks again."""
	_ready_at.erase(game)
	_asked_by = ""


static func ready_games() -> Array[String]:
	var out: Array[String] = []
	var now: int = int(Time.get_unix_time_from_system())
	for game in _ready_at:
		if int(_ready_at[game]) <= now:
			out.append(String(game))
	return out


static func has_a_run() -> bool:
	"""A game you may go into now. Opening the card does not change it."""
	return not ready_games().is_empty()


func paint_news() -> void:
	"""The bar's Minigames dot. Out inside the Endless (Leave is the button)."""
	if hud != null and hud.has_method("mark_minigames_button"):
		hud.call("mark_minigames_button", has_a_run() and not inside_endless())


# =============================================================================
# OPEN, CLOSE, AND WHAT IT SAYS
# =============================================================================

func toggle() -> void:
	if visible:
		close()
	else:
		open()


func close() -> bool:
	var was: bool = visible
	visible = false
	set_process(false)
	return was


func open() -> void:
	_leave_armed = false
	_forge_leave_armed = false
	_forge_failed = false
	_healer_said = ""
	visible = true
	move_to_front()
	_known = false
	_failed = false
	paint()
	_place()
	set_process(true)
	if inside_endless():
		return
	var res: Dictionary = await list_request.call("/api/minigames", 6.0)
	if not is_instance_valid(self) or not visible:
		return
	take_listing(res)


func take_listing(res: Dictionary) -> void:
	"""The server's answer to GET /api/minigames: this card's minigame's wait."""
	_known = false
	if res.get("ok", false) and res.get("data") is Dictionary:
		for game in (res["data"] as Dictionary).get("games", []):
			if game is Dictionary and str(game.get("id", "")) == HEALER_GAME:
				healer_left = maxi(0, int(game.get("plays_left", 3)))
				healer_wait = maxi(0, int(game.get("ready_in", 0)))
				_healer_said_msec = Time.get_ticks_msec()
				_healer_known = true
				note_wait(HEALER_GAME, 0 if healer_left > 0 else healer_wait)
			if game is Dictionary and str(game.get("id", "")) == CLOTH_GAME:
				cloth_left = maxi(0, int(game.get("plays_left", 3)))
				cloth_wait = maxi(0, int(game.get("ready_in", 0)))
				_cloth_said_msec = Time.get_ticks_msec()
				_cloth_known = true
				if bool(shows_cloth.call()):
					note_wait(CLOTH_GAME, 0 if cloth_left > 0 else cloth_wait)
			if game is Dictionary and str(game.get("id", "")) == FORGE:
				forge_wait = maxi(0, int(game.get("ready_in", 0)))
				forge_best = maxi(0, int(game.get("best", 0)))
				_forge_said_msec = Time.get_ticks_msec()
				_forge_known = true
				# Its dot only for somebody the card shows it to.
				if bool(shows_forge.call()):
					note_wait(FORGE, forge_wait)
			if game is Dictionary and str(game.get("id", "")) == GAME:
				ready_in = maxi(0, int(game.get("ready_in", 0)))
				_said_at_msec = Time.get_ticks_msec()
				_known = true
				note_wait(GAME, ready_in)
	_failed = not _known
	paint()
	paint_news()


func inside_endless() -> bool:
	return str(area_now.call()) == GAME


func left_now() -> int:
	"""Seconds of the wait still left, counted down from the server's word."""
	if not _known:
		return 0
	@warning_ignore("integer_division")
	return maxi(0, ready_in - int((Time.get_ticks_msec() - _said_at_msec) / 1000))


static func wait_text(seconds: int) -> String:
	"""'Back in 13h 20m' - how the card says a wait (the server's words)."""
	if seconds < 60:
		return "Back in under a minute"
	@warning_ignore("integer_division")
	var hours: int = seconds / 3600
	@warning_ignore("integer_division")
	var minutes: int = (seconds % 3600) / 60
	if hours > 0 and minutes > 0:
		return "Back in %dh %dm" % [hours, minutes]
	if hours > 0:
		return "Back in %dh" % hours
	return "Back in %dm" % minutes


func paint() -> void:
	"""The status line and the button, from what is known now."""
	_paint_healer()
	_paint_stand()
	_paint_descent()
	_paint_forge()
	_paint_cloth()
	if inside_endless():
		var held: int = chest_held()
		if held > 0:
			status.text = "Your chest holds %d. Leave it and your next Go empties it." % held
			status.add_theme_color_override("font_color", COLOUR_WAIT)
		else:
			status.text = "You are in the Endless."
			status.add_theme_color_override("font_color", COLOUR_HINT)
		go_button.text = "Leave anyway" if _leave_armed and held > 0 else "Leave"
		go_button.tooltip_text = "Back up to town"
		go_button.disabled = _busy
		return
	go_button.text = "Go"
	go_button.tooltip_text = "Down to the Endless's corridor - your day starts now"
	var left: int = left_now()
	if left > 0:
		status.text = wait_text(left)
		status.add_theme_color_override("font_color", COLOUR_WAIT)
		go_button.disabled = true
	elif _failed:
		status.text = UNREACHABLE
		status.add_theme_color_override("font_color", COLOUR_WAIT)
		go_button.disabled = _busy
	elif _busy or not _known:
		status.text = "Asking the server..."
		status.add_theme_color_override("font_color", COLOUR_HINT)
		go_button.disabled = true
	else:
		status.text = "Ready"
		status.add_theme_color_override("font_color", COLOUR_READY)
		go_button.disabled = false


func _process(_delta: float) -> void:
	# The wait counts down while the card is open, once a frame is plenty.
	if _known and not inside_endless():
		var was: String = status.text
		paint()
		if status.text != was:
			_place()


func _place() -> void:
	"""Above the Minigames button, its right edge on the button's - as the
	bar's dropdowns stand (characterhud.gd nav_menu_position())."""
	if not is_inside_tree():
		return
	reset_size()
	var screen: Vector2 = get_viewport_rect().size
	var button: Control = hud.get_node_or_null("%minigamesbutton") as Control if hud != null else null
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	var anchor := Rect2(Vector2(screen.x / 2.0, screen.y - 48.0), Vector2.ZERO)
	if button != null and button.is_visible_in_tree():
		anchor = button.get_global_rect()
	elif nav != null:
		anchor = Rect2(nav.get_global_rect().position + Vector2(size.x, 0), Vector2.ZERO)
	var x: float = clampf(anchor.end.x - size.x, 0.0, maxf(0.0, screen.x - size.x))
	var y: float = maxf(0.0, anchor.position.y - size.y - GAP)
	position = Vector2(x, y).floor()


# =============================================================================
# GO AND LEAVE
# =============================================================================

func _on_go() -> void:
	if _busy:
		return
	if inside_endless():
		if chest_held() > 0 and not _leave_armed:
			_leave_armed = true
			paint()
			_place()
			return
		_leave_armed = false
		close()
		travel.call(TOWN, "")
		return
	_busy = true
	_failed = false
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter", {"game": GAME}, 6.0)
	if not is_instance_valid(self):
		return
	_busy = false
	if res.get("ok", false):
		forget_wait(GAME)
		close()
		travel.call(GAME, ENTRANCE)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if int(res.get("status", 0)) == 409:
		# THE SERVER'S DAY: how long it says, counted down from here.
		ready_in = maxi(0, int(data.get("ready_in", 0)))
		_said_at_msec = Time.get_ticks_msec()
		_known = true
		note_wait(GAME, ready_in)
		paint()
		return
	_failed = true
	paint()


func _paint_healer() -> void:
	healer_box.visible = bool(shows_healer_run.call())
	var in_town: bool = str(area_now.call()) == TOWN
	@warning_ignore("integer_division")
	var wait_left: int = maxi(0, healer_wait - int((Time.get_ticks_msec() - _healer_said_msec) / 1000)) \
		if _healer_known else 0
	var none_left: bool = _healer_known and healer_left <= 0 and wait_left > 0
	if _healer_said != "":
		healer_status.text = _healer_said
	elif not in_town:
		healer_status.text = FROM_TOWN
	elif none_left:
		healer_status.text = wait_text(wait_left)
	elif _healer_known:
		healer_status.text = "Ready - %d of 3 runs left today" % healer_left
	else:
		healer_status.text = "Ready"
	var go_on: bool = in_town and not none_left and not _healer_busy
	healer_status.add_theme_color_override("font_color", COLOUR_READY if go_on else (COLOUR_WAIT if none_left else COLOUR_HINT))
	healer_go.disabled = not go_on
	healer_go.tooltip_text = "Play the Healer's Run - your character waits in town" if in_town \
		else "Go back to town first"


func _on_healer_go() -> void:
	if str(area_now.call()) != TOWN or _healer_busy:
		paint()
		return
	if bool(healer_party.call()):
		# WITH THE PARTY: the start panel first; the run is asked for at the count.
		close()
		open_lobby.call()
		return
	_healer_busy = true
	_healer_said = "Asking the server..."
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter",
		{"game": HEALER_GAME, "slot": int(CharacterData.active_character_index)}, 6.0)
	_healer_busy = false
	_healer_said = ""
	if not is_instance_valid(self):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		healer_left = maxi(0, int(data.get("plays_left", 0)))
		if healer_left <= 0:
			forget_wait(HEALER_GAME)
		close()
		open_run.call(int(data["run"]), data.get("pays", {}) if data.get("pays") is Dictionary else {})
		return
	if int(res.get("status", 0)) == 409:
		healer_left = 0
		healer_wait = maxi(0, int(data.get("ready_in", 0)))
		_healer_said_msec = Time.get_ticks_msec()
		_healer_known = true
		note_wait(HEALER_GAME, healer_wait)
	else:
		_healer_said = UNREACHABLE
	paint()


func _shows_healer_run() -> bool:
	return true


func _paint_stand() -> void:
	stand_box.visible = bool(shows_mage_stand.call())
	var in_town: bool = str(area_now.call()) == TOWN
	stand_status.text = "Ready - no limit on meteors" if in_town else FROM_TOWN
	stand_status.add_theme_color_override("font_color", COLOUR_READY if in_town else COLOUR_HINT)
	stand_go.disabled = not in_town
	stand_go.tooltip_text = "Play the Mage's Stand - your character waits in town" if in_town \
		else "Go back to town first"


func _on_stand_go() -> void:
	if str(area_now.call()) != TOWN or not bool(shows_mage_stand.call()):
		paint()
		return
	close()
	open_stand.call()


func _paint_descent() -> void:
	descent_box.visible = bool(shows_descent.call())
	var inside: bool = str(area_now.call()) == DESCENT
	if inside:
		descent_status.text = "You are in the Descent."
	else:
		descent_status.text = "Ready - down you go, as you are"
	descent_status.add_theme_color_override("font_color", COLOUR_HINT if inside else COLOUR_READY)
	descent_go.text = "Leave" if inside else "Go"
	descent_go.disabled = false
	descent_go.tooltip_text = "Back up to town" if inside else "Down into the Descent - as you are, gear and all"


func _on_descent_go() -> void:
	if not bool(shows_descent.call()):
		paint()
		return
	if str(area_now.call()) == DESCENT:
		close()
		travel.call(TOWN, "")
	else:
		close()
		travel.call(DESCENT, DESCENT_ENTRANCE)


func _shows_descent() -> bool:
	return bool(Api.is_owner)


# THE FORGE'S DAY (0.120.0). The owner: "Rewards + daily wait". Go asks the
# server first (POST /api/minigames/enter, "forge"): once a day, as the
# Endless, and the fire sprites pay into the chest by the island's arrival
# only inside it. The status says the best time the server keeps. Inside,
# Leave asks twice while the chest holds loot - the next Go empties it.
static func best_text(seconds: int) -> String:
	@warning_ignore("integer_division")
	return "" if seconds <= 0 else "best %d:%02d" % [seconds / 60, seconds % 60]


func forge_left_now() -> int:
	if not _forge_known:
		return 0
	@warning_ignore("integer_division")
	return maxi(0, forge_wait - int((Time.get_ticks_msec() - _forge_said_msec) / 1000))


func _paint_forge() -> void:
	forge_box.visible = bool(shows_forge.call())
	var inside: bool = str(area_now.call()) == FORGE
	var best: String = best_text(forge_best)
	var colour: Color = COLOUR_READY
	forge_go.disabled = _forge_busy
	if inside:
		var held: int = chest_held()
		forge_status.text = "Your chest holds %d. Leave it and your next Go empties it." % held if held > 0 \
			else "You are in the Forge."
		colour = COLOUR_WAIT if held > 0 else COLOUR_HINT
		forge_go.text = "Leave anyway" if _forge_leave_armed and held > 0 else "Leave"
		forge_go.tooltip_text = "Back up to town"
	else:
		forge_go.text = "Go"
		forge_go.tooltip_text = "Down into the Forge, as you are - your day starts now"
		var left: int = forge_left_now()
		if left > 0:
			forge_status.text = wait_text(left) + ("  ·  " + best if best != "" else "")
			colour = COLOUR_WAIT
			forge_go.disabled = true
		elif _forge_failed:
			forge_status.text = UNREACHABLE
			colour = COLOUR_WAIT
		elif _forge_busy:
			forge_status.text = "Asking the server..."
			colour = COLOUR_HINT
		else:
			forge_status.text = "Ready  ·  " + best if best != "" else "Ready - any class goes down"
	forge_status.add_theme_color_override("font_color", colour)


func _on_forge_go() -> void:
	if not bool(shows_forge.call()) or _forge_busy:
		paint()
		return
	if str(area_now.call()) == FORGE:
		if chest_held() > 0 and not _forge_leave_armed:
			_forge_leave_armed = true
			paint()
			_place()
			return
		_forge_leave_armed = false
		close()
		travel.call(TOWN, "")
		return
	_forge_busy = true
	_forge_failed = false
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter", {"game": FORGE}, 6.0)
	if not is_instance_valid(self):
		return
	_forge_busy = false
	if res.get("ok", false):
		forget_wait(FORGE)
		close()
		travel.call(FORGE, FORGE_ENTRANCE)
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if int(res.get("status", 0)) == 409:
		forge_wait = maxi(0, int(data.get("ready_in", 0)))
		_forge_said_msec = Time.get_ticks_msec()
		_forge_known = true
		note_wait(FORGE, forge_wait)
	else:
		_forge_failed = true
	paint()


func _shows_forge() -> bool:
	return bool(Api.is_owner)


func _shows_mage_stand() -> bool:
	return bool(Api.is_owner)


func _paint_cloth() -> void:
	cloth_box.visible = bool(shows_cloth.call())
	var in_town: bool = str(area_now.call()) == TOWN
	@warning_ignore("integer_division")
	var wait_left: int = maxi(0, cloth_wait - int((Time.get_ticks_msec() - _cloth_said_msec) / 1000)) \
		if _cloth_known else 0
	var none_left: bool = _cloth_known and cloth_left <= 0 and wait_left > 0
	if _cloth_said != "":
		cloth_status.text = _cloth_said
	elif not in_town:
		cloth_status.text = FROM_TOWN
	elif none_left:
		cloth_status.text = wait_text(wait_left)
	elif _cloth_known:
		cloth_status.text = "Ready - %d of 3 runs left today" % cloth_left
	else:
		cloth_status.text = "Ready"
	var go_on: bool = in_town and not none_left and not _cloth_busy
	cloth_status.add_theme_color_override("font_color", COLOUR_READY if go_on else (COLOUR_WAIT if none_left else COLOUR_HINT))
	cloth_go.disabled = not go_on
	cloth_go.tooltip_text = "Play Cut the Cloth - your character waits in town" if in_town \
		else "Go back to town first"


func _on_cloth_go() -> void:
	"""Go: the server asked for a run of the day first; let in, the screen
	opens on it."""
	if str(area_now.call()) != TOWN or not bool(shows_cloth.call()) or _cloth_busy:
		paint()
		return
	_cloth_busy = true
	_cloth_said = "Asking the server..."
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter",
		{"game": CLOTH_GAME, "slot": int(CharacterData.active_character_index)}, 6.0)
	_cloth_busy = false
	_cloth_said = ""
	if not is_instance_valid(self):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		cloth_left = maxi(0, int(data.get("plays_left", 0)))
		if cloth_left <= 0:
			forget_wait(CLOTH_GAME)
		close()
		open_cloth.call(int(data["run"]), data.get("pays", {}) if data.get("pays") is Dictionary else {})
		return
	if int(res.get("status", 0)) == 409:
		cloth_left = 0
		cloth_wait = maxi(0, int(data.get("ready_in", 0)))
		_cloth_said_msec = Time.get_ticks_msec()
		_cloth_known = true
		note_wait(CLOTH_GAME, cloth_wait)
	else:
		_cloth_said = UNREACHABLE
	paint()


func _shows_cloth() -> bool:
	return bool(Api.is_owner)


func _open_cloth(run_id: int = 0, what_it_pays: Dictionary = {}) -> void:
	(load("res://src/world/cloth/clothscreen.gd") as GDScript).call("open", get_tree(), hud, run_id, what_it_pays)


func _open_stand() -> void:
	(load("res://src/world/magestand/magestandscreen.gd") as GDScript).call("open", get_tree(), hud)


func _open_run(run_id: int = 0, what_it_pays: Dictionary = {}) -> void:
	(load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).call("open", get_tree(), 0, run_id,
		what_it_pays, hud)


func _healer_party() -> bool:
	return Presence.healer_rooms() and Party.members.size() > 1


func _open_lobby() -> void:
	(load("res://src/world/healerrun/healerrunscreen.gd") as GDScript).call("open", get_tree(), 0, 0, {}, hud, true)


func chest_held() -> int:
	return maxi(0, int(chest_count.call())) if chest_count.is_valid() else 0


func _chest_count() -> int:
	var chest: Node = get_tree().get_first_node_in_group(&"endless_chest") if is_inside_tree() else null
	return int(chest.get("used")) if chest != null and "used" in chest else 0


func _travel(area_id: String, spawn_id: String) -> void:
	GameState.next_spawn_id = spawn_id
	AreaRegistry.go_to(area_id)
