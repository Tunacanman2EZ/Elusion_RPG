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
# while it was built, everyone's since 0.158.0 (`shows_mage_stand`): Go, in
# town, opens it - it pays nothing, so nothing is asked of the server.
#
# THE DESCENT (0.112.0, descentrun.gd) is the fourth, the owner's alone while
# it was built, everyone's since 0.158.0 (`shows_descent`): THE WARRIOR'S (the owner: "this will be the
# warriors decent", as the Healer's Run is the healer's and the Stand the
# mage's), a roguelike run down a crypt as your own warrior. Go, playing a
# warrior (`class_now`), travels there (its own area, as the Endless is) and
# asks the server nothing - step 1 pays nothing; inside it, the row's button
# is Leave, to town.
#
# THE FORGE (forgerun.gd) is the fifth, the owner's alone while it was built,
# everyone's since 0.158.0 (`shows_forge`): THE TANK'S WORLD - an island in a lake of lava that floods
# slice by slice - but open to every class (the owner: "open to any class but
# the tank benefits the most"). Go asks the server first since 0.120.0 -
# once a day, as the Endless, and the status says your best time - then
# travels there (its own area, as the Descent is); inside it, the row's button
# is Leave, to town, asked twice while the chest holds loot.
#
# CUT THE CLOTH (0.130.0, clothrun.gd) is the sixth, the owner's alone while
# it was built, everyone's since 0.158.0 (`shows_cloth`): the old map's slime plague cut away piece by
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
# ALL SIX OPEN (0.158.0). The owner, of the site calling four of them
# "coming soon": "they are not coming soon they are already out" - and
# chose to open them for everyone. Each `shows_*` is true, as the Healer's
# Run's has been since 0.99.0 (the seams stay, for the suite), and no tile
# carries TESTING. TAG_TESTING is kept for the next game built.
#
# CROWNFALL (0.162.0, crownfall/) is the seventh, the owner's alone while it
# is built (`shows_crownfall`, TESTING): a brick breaker through seven monster
# kingdoms, played over the screen from town like the Cloth. Three runs a
# day: Go asks the server (game "crownfall") and opens the run with its id,
# what each map pays and how far the account has got (`progress`); the
# listing says the runs left and how many maps are cleared. Any class.
#
# THE BEHOLDER'S TABLE (0.167.0, pinball/) is the eighth, the owner's alone
# while it is built (`shows_pinball`, TESTING): a pinball table in three
# floors, played over the screen from town like Crownfall. Since 0.168.0 Go
# asks the server for one of the day's three paid games (game "pinball") and
# opens on it with its gold's table and the account's best; with none left
# it opens as practice at once, and the tile says when the next one is.
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
const CrownMaps := preload("res://src/world/crownfall/crownfallmaps.gd")
const COLOUR_HINT := Color(0.82, 0.78, 0.7)
const COLOUR_READY := Color(0.6, 0.9, 0.55)
const COLOUR_WAIT := Color(1.0, 0.72, 0.4)
const FONT_SIZE := 14
# A GRID OF CARDS (0.168.1). The owner: "we have to remake the minigames
# hud because I cannot see the new minigame" - nine tiles in one column
# stood 680 of the screen's 720 high, and the ninth fell under the bar.
# Two columns of TILE_W now, in a scroll that holds the card to the room
# above the bar (`_place()`); a tap anywhere on a game's card is its Go
# (`_on_tile_input()`). The tiles' words wrap at TEXT_W, their tags on a
# line under the name.
const TILE_W := 396.0
const TEXT_W := 246.0
const COLUMNS := 2
const WIDTH := TILE_W * 2.0 + 6.0
const GAP := 6.0
const STATUS_WIDTH := TEXT_W
# the least of the list shown when the room is short; a tap that moved
# further than TAP_SLOP was a drag of the scroll, not a Go
const SCROLL_LEAST := 160.0
const TAP_SLOP := 12.0
const GAME := "endless"
const ENTRANCE := "endless_entrance"
const TOWN := "elusion"
const BLURB := "A horde that never stops."
const UNREACHABLE := "Could not reach the server - try again."
const OPENING := "Opening the table..."
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
const CROWN_BLURB := "Break the plague-stone walls of the monster kingdoms."
const CROWN_GAME := "crownfall"
const PIN_GAME := "pinball"
# CROWNFALL'S PICTURE IS DRAWN HERE (0.168.0): its tile pointed at the large
# light slime, an inherited scene, and `portrait_of()` never looked in the
# scene it inherits, so the tile stood empty (the Testing Ground's skeleton
# elite too; it looks there now). For Crownfall the owner chose instead a
# wall of the seven lands' bricks in Crownfall's own colours
# (LAND_COLOURS, held to crownfallrun.gd's COLOURS by the suite), three
# broken out, the ball and the paddle - `bricks_picture()`, asked for by
# BRICKS in PORTRAITS. No art file: every pixel is set in code.
const BRICKS := "drawn:crownfall"
const LAND_ORDER := ["light", "wind", "water", "ice", "earth", "fire", "dark"]
const LAND_COLOURS := {
	"dark": Color(0.427, 0.157, 0.851), "fire": Color(1.0, 0.416, 0.122), "earth": Color(0.631, 0.384, 0.027),
	"ice": Color(0.404, 0.91, 0.976), "water": Color(0.231, 0.51, 0.965), "wind": Color(0.655, 0.953, 0.816),
	"light": Color(0.992, 0.902, 0.541),
}
# THE TILES (0.119.1): each game's portrait (a scene whose sprite is the
# picture), its rim, and its tags - [words, colour, what it means].
const PORTRAITS := {
	"endless": ["res://scene/enemy/poisonslime.tscn", Color(0.55, 0.85, 0.35)],
	"healerrun": ["res://scene/characters/healer.tscn", Color(0.45, 0.9, 0.6)],
	"magestand": ["res://scene/characters/mage.tscn", Color(0.45, 0.65, 1.0)],
	"descent": ["res://scene/characters/warrior.tscn", Color(0.95, 0.4, 0.35)],
	"forge": ["res://scene/characters/tank.tscn", Color(1.0, 0.6, 0.25)],
	"cloth": ["res://scene/projectiles/turretprojectile.tscn", Color(0.86, 0.77, 0.61)],
	"crownfall": [BRICKS, Color(1.0, 0.82, 0.38)],
	"testingground": ["res://scene/enemy/skeletonelite.tscn", Color(0.8, 0.35, 0.3)],
	"pinball": ["res://scene/enemy/bossenemy.tscn", Color(0.65, 0.45, 1.0)],
}
const TAG_DAILY := ["DAILY", Color(0.35, 0.3, 0.6), "Once a day"]
const TAG_THREE := ["3 A DAY", Color(0.35, 0.3, 0.6), "Three runs a day"]
# Not on any tile since 0.158.0 (every game is open); the next game built
# wears it while its `shows_*` is the owner's.
const TAG_TESTING := ["TESTING", Color(0.55, 0.35, 0.1), "Yours only while it is built"]
# THE TESTING GROUND (0.151.1, testingground.gd): the owner's alone.
const TAG_OWNER := ["OWNER", Color(0.5, 0.15, 0.15), "Yours only - for measuring"]
const PINBALL_BLURB := "The Beholder's Table: pinball in three floors - the town, the field, his lair."
const TESTING_BLURB := "The Endless's arena with nothing in it - measure what each monster costs."
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
# Crownfall's: who sees it (the owner, while it is built) and Go.
var shows_crownfall: Callable = Callable(self, "_shows_crownfall")
var open_crownfall: Callable = Callable(self, "_open_crownfall")

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
var crown_box: PanelContainer = null
var crown_status: Label = null
var crown_go: Button = null
var pinball_box: PanelContainer = null
var pinball_status: Label = null
var pinball_go: Button = null
# The table's: who sees it (the owner, while it is built) and Go.
var shows_pinball: Callable = func() -> bool: return bool(Api.is_owner)
var open_pinball: Callable = Callable(self, "_open_pinball")
var testing_box: PanelContainer = null
var testing_status: Label = null
var testing_go: Button = null
# Seams for the suite: the owner, and whether in a party.
var shows_testing: Callable = func() -> bool: return bool(Api.is_owner)
var in_party: Callable = func() -> bool: return Party.in_one()
# Cut the Cloth's runs left today and the wait when none are, as the server
# said and when.
var cloth_left: int = 3
var cloth_wait: int = 0
var _cloth_known: bool = false
var _cloth_said_msec: int = 0
var _cloth_busy: bool = false
var _cloth_said: String = ""
# Crownfall's the same, and how many of its maps the account has cleared.
var crown_left: int = 3
var crown_wait: int = 0
var crown_progress: int = 0
# The Beholder's Table's the same, and the account's best score.
var pin_left: int = 3
var pin_wait: int = 0
var pin_best: int = 0
var _pin_known: bool = false
var _pin_said_msec: int = 0
var _pin_busy: bool = false
var _pin_said: String = ""
var _crown_known: bool = false
var _crown_said_msec: int = 0
var _crown_busy: bool = false
var _crown_said: String = ""
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


var scroller: ScrollContainer = null
var grid: GridContainer = null


static func attach(on_hud: Node, later: bool = false) -> Control:
	"""The card on `on_hud`, shut. `later` (the HUD's): its tiles made the
	first time it is painted or opened, not as the HUD arrives (TILES WHEN
	WANTED)."""
	var card: Control = (load("res://src/ui/minigames/minigamescard.gd") as GDScript).new()
	card.name = "minigamescard"
	card.set("hud", on_hud)
	card.set("tiles_later", later)
	on_hud.add_child(card)
	return card


# TILES WHEN WANTED (0.176.1, the owner: "we must refine deeper into my
# game"). The HUD is made again in every area, and its card's nine tiles -
# a portrait, words, tags and a button each - were 9 ms of every arrival
# (zz/hudcost: 22 ms the HUD's whole add), for a card most arrivals never
# open. The HUD's card makes them the first time it is painted or opened
# (_build_tiles()); paint_news() - the bar's dot - needs none of them.
var tiles_later: bool = false
var built: bool = false


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
	scroller = ScrollContainer.new()
	scroller.name = "scroller"
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroller)
	grid = GridContainer.new()
	grid.name = "grid"
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(grid)


func _build_tiles() -> void:
	"""Each minigame's tile, once (TILES WHEN WANTED)."""
	if built:
		return
	built = true
	var endless: Array = _tile(grid, "endless", "The Endless", BLURB, [TAG_DAILY])
	endless_box = endless[0]
	game_name = endless[1]
	blurb = endless[2]
	status = endless[3]
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go_button = _go_button("go", _on_go)
	(endless[4] as HBoxContainer).add_child(go_button)
	var healer: Array = _tile(grid, "healerrun", "The Healer's Run", HEALER_BLURB,
		[TAG_THREE, ["HEALER", Color(0.2, 0.45, 0.3), "The healer's"]])
	healer_box = healer[0]
	healer_status = healer[3]
	healer_go = _go_button("healergo", _on_healer_go)
	(healer[4] as HBoxContainer).add_child(healer_go)
	var stand: Array = _tile(grid, "magestand", "The Mage's Stand", STAND_BLURB,
		[["MAGE", Color(0.2, 0.3, 0.55), "The mage's"]])
	stand_box = stand[0]
	stand_status = stand[3]
	stand_go = _go_button("standgo", _on_stand_go)
	(stand[4] as HBoxContainer).add_child(stand_go)
	var descent: Array = _tile(grid, "descent", "The Descent", DESCENT_BLURB,
		[["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go - each with its own upgrades"]])
	descent_box = descent[0]
	descent_status = descent[3]
	descent_go = _go_button("descentgo", _on_descent_go)
	(descent[4] as HBoxContainer).add_child(descent_go)
	var forge: Array = _tile(grid, "forge", "The Forge", FORGE_BLURB,
		[TAG_DAILY, ["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go"],
		["TANK BEST", Color(0.55, 0.3, 0.12), "The tank's world - he lasts longest"]])
	forge_box = forge[0]
	forge_status = forge[3]
	forge_go = _go_button("forgego", _on_forge_go)
	(forge[4] as HBoxContainer).add_child(forge_go)
	var cloth: Array = _tile(grid, "cloth", "Cut the Cloth", CLOTH_BLURB,
		[TAG_THREE, ["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go"]])
	cloth_box = cloth[0]
	cloth_status = cloth[3]
	cloth_go = _go_button("clothgo", _on_cloth_go)
	(cloth[4] as HBoxContainer).add_child(cloth_go)
	var crown: Array = _tile(grid, "crownfall", "Crownfall", CROWN_BLURB,
		[TAG_THREE, TAG_TESTING, ["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go"]])
	crown_box = crown[0]
	crown_status = crown[3]
	crown_go = _go_button("crowngo", _on_crown_go)
	(crown[4] as HBoxContainer).add_child(crown_go)
	var table: Array = _tile(grid, "pinball", "The Beholder's Table", PINBALL_BLURB,
		[TAG_TESTING, ["ANY CLASS", Color(0.3, 0.3, 0.32), "Every class may go"]])
	pinball_box = table[0]
	pinball_status = table[3]
	pinball_go = _go_button("pinballgo", _on_pinball_go)
	(table[4] as HBoxContainer).add_child(pinball_go)
	var testing: Array = _tile(grid, "testingground", "Testing Ground", TESTING_BLURB, [TAG_OWNER])
	testing_box = testing[0]
	testing_status = testing[3]
	testing_go = _go_button("testinggo", _on_testing_go)
	(testing[4] as HBoxContainer).add_child(testing_go)
	for tile in grid.get_children():
		var go: Button = ((tile as Control).get_child(0) as Control).get_child(-1) as Button
		(tile as Control).gui_input.connect(_on_tile_input.bind(tile, go))
		(tile as Control).mouse_entered.connect(_hover.bind(tile, true))
		(tile as Control).mouse_exited.connect(_hover.bind(tile, false))


func _tile(column: Control, id: String, game_title: String, line: String, tags: Array) -> Array:
	"""A game's tile in `column`: [tile, its name, its line, its status, the
	row its Go goes in]."""
	var tile := PanelContainer.new()
	tile.name = id
	tile.add_theme_stylebox_override("panel", _flat(TILE_BG, Color(COLOUR, 0.28), 4, 6, 1))
	tile.custom_minimum_size = Vector2(TILE_W, 0)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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
	var name_label: Label = _label(id + "game", game_title, FONT_SIZE, COLOUR)
	words.add_child(name_label)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	words.add_child(head)
	for tag in tags:
		head.add_child(_tag(tag))
	var line_label: Label = _label(id + "blurb", line, 11, COLOUR_HINT)
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_label.custom_minimum_size = Vector2(TEXT_W, 0)
	words.add_child(line_label)
	var state: Label = _label(id + "status", "", 12, COLOUR_HINT)
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	words.add_child(state)
	return [tile, name_label, line_label, state, row]


func _on_tile_input(event: InputEvent, tile: Control, go: Button) -> void:
	"""A tap on a game's card, anywhere off its Go, is its Go - unless the
	finger moved, which was a drag of the scroll."""
	if not (event is InputEventMouseButton) or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var press: InputEventMouseButton = event
	if press.pressed:
		tile.set_meta("down_at", press.global_position)
		return
	if not tile.has_meta("down_at"):
		return
	var from: Vector2 = tile.get_meta("down_at")
	tile.remove_meta("down_at")
	if press.global_position.distance_to(from) > TAP_SLOP or go.disabled or not go.is_visible_in_tree():
		return
	tile.accept_event()
	go.pressed.emit()


func _hover(tile: Control, on: bool) -> void:
	"""A card under the mouse lights its rim."""
	tile.add_theme_stylebox_override("panel", _flat(TILE_BG, Color(COLOUR, 0.7 if on else 0.28), 4, 6, 1))


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
	if scene_path == BRICKS:
		_portraits[scene_path] = ImageTexture.create_from_image(bricks_picture())
		return _portraits[scene_path]
	var picture: Texture2D = null
	var packed: PackedScene = load(scene_path) as PackedScene if scene_path != "" and ResourceLoader.exists(scene_path) else null
	# An inherited scene (the skeleton elite on the skeleton) keeps its sprite
	# in the scene it inherits, so look there too (0.168.0: the Testing
	# Ground's tile stood empty).
	var state: SceneState = packed.get_state() if packed != null else null
	while state != null and picture == null:
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
		state = state.get_base_scene_state()
	_portraits[scene_path] = picture
	return picture


static func bricks_picture() -> Image:
	"""Crownfall's tile: the seven lands' bricks, light at the top and dark
	at the foot, every other row set off half a brick, three broken out
	where the ball went through; the ball, its trail and the paddle. The
	portrait's own size (PORTRAIT_SIZE less its rim), one pixel a pixel."""
	var side: int = int(PORTRAIT_SIZE) - 4
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var broken: Array = [Vector2i(3, 5), Vector2i(2, 6), Vector2i(3, 6)]
	for row in LAND_ORDER.size():
		var shift: int = 0 if row % 2 == 0 else -4
		for col in 6:
			if Vector2i(col, row) in broken:
				continue
			_pixel_brick(image, Rect2i(shift + col * 8, 1 + row * 4, 8, 3), LAND_COLOURS[LAND_ORDER[row]])
	var gold := Color(1.0, 0.82, 0.38)
	for step in 4:
		var at := Vector2i(16 + step * 2, 42 - step * 2)
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(at):
			image.set_pixelv(at, image.get_pixelv(at).blend(Color(gold, 0.15 + 0.12 * step)))
	_pixel_brick(image, Rect2i(23, 33, 3, 3), Color(1.0, 0.95, 0.75))
	image.set_pixel(24, 32, Color.WHITE)
	_pixel_brick(image, Rect2i(14, 39, 16, 3), Color(0.85, 0.82, 0.78))
	return image


static func _pixel_brick(image: Image, box: Rect2i, colour: Color) -> void:
	"""One brick, a pixel at a time: lit along its top, shaded along its
	foot and right side; whatever falls off the picture is left out."""
	var whole := Rect2i(Vector2i.ZERO, image.get_size())
	for i in box.size.x:
		for j in box.size.y:
			var at := box.position + Vector2i(i, j)
			if not whole.has_point(at):
				continue
			var c: Color = colour
			if j == 0:
				c = colour.lightened(0.35)
			elif j == box.size.y - 1 or i == box.size.x - 1:
				c = colour.darkened(0.35)
			image.set_pixelv(at, c)

func _label(id: String, text: String, font_px: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.add_theme_font_size_override("font_size", font_px)
	label.add_theme_color_override("font_color", colour)
	return label


func _ready() -> void:
	if not tiles_later:
		_build_tiles()
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
			if game is Dictionary and str(game.get("id", "")) == CROWN_GAME:
				crown_left = maxi(0, int(game.get("plays_left", 3)))
				crown_wait = maxi(0, int(game.get("ready_in", 0)))
				crown_progress = maxi(0, int(game.get("progress", 0)))
				_crown_said_msec = Time.get_ticks_msec()
				_crown_known = true
				if bool(shows_crownfall.call()):
					note_wait(CROWN_GAME, 0 if crown_left > 0 else crown_wait)
			if game is Dictionary and str(game.get("id", "")) == PIN_GAME:
				pin_left = maxi(0, int(game.get("plays_left", 3)))
				pin_wait = maxi(0, int(game.get("ready_in", 0)))
				pin_best = maxi(pin_best, int(game.get("best_score", 0)))
				_pin_said_msec = Time.get_ticks_msec()
				_pin_known = true
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


static func score_words(n: int) -> String:
	"""1234567 as '1,234,567'."""
	var digits: String = str(maxi(0, n))
	var out: String = ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


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
	_build_tiles()
	_paint_healer()
	_paint_stand()
	_paint_descent()
	_paint_forge()
	_paint_cloth()
	_paint_crown()
	_paint_testing()
	_paint_pinball()
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
	var whole: float = grid.get_combined_minimum_size().y
	scroller.custom_minimum_size.y = whole
	reset_size()
	var screen: Vector2 = get_viewport_rect().size
	var button: Control = hud.get_node_or_null("%minigamesbutton") as Control if hud != null else null
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	var anchor := Rect2(Vector2(screen.x / 2.0, screen.y - 48.0), Vector2.ZERO)
	if button != null and button.is_visible_in_tree():
		anchor = button.get_global_rect()
	elif nav != null:
		anchor = Rect2(nav.get_global_rect().position + Vector2(size.x, 0), Vector2.ZERO)
	# never taller than the room above the bar: the list scrolls instead
	var room: float = anchor.position.y - GAP
	if size.y > room:
		scroller.custom_minimum_size.y = maxf(SCROLL_LEAST, whole - (size.y - room))
		reset_size()
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
		# A run, not the Testing Ground.
		GameState.testing_ground = false
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
	return true


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
	return true


func _shows_mage_stand() -> bool:
	return true


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


func _paint_crown() -> void:
	crown_box.visible = bool(shows_crownfall.call())
	var in_town: bool = str(area_now.call()) == TOWN
	@warning_ignore("integer_division")
	var wait_left: int = maxi(0, crown_wait - int((Time.get_ticks_msec() - _crown_said_msec) / 1000)) \
		if _crown_known else 0
	var none_left: bool = _crown_known and crown_left <= 0 and wait_left > 0
	if _crown_said != "":
		crown_status.text = _crown_said
	elif not in_town:
		crown_status.text = FROM_TOWN
	elif none_left:
		crown_status.text = wait_text(wait_left)
	elif _crown_known:
		crown_status.text = "Ready - %d of 3 runs left today · %d of %d maps cleared" % [crown_left,
			mini(crown_progress, CrownMaps.made_count()), CrownMaps.made_count()]
	else:
		crown_status.text = "Ready"
	var go_on: bool = in_town and not none_left and not _crown_busy
	crown_status.add_theme_color_override("font_color", COLOUR_READY if go_on else (COLOUR_WAIT if none_left else COLOUR_HINT))
	crown_go.disabled = not go_on
	crown_go.tooltip_text = "Play Crownfall - your character waits in town" if in_town else "Go back to town first"


func _on_crown_go() -> void:
	"""Go: the server asked for a run of the day first; let in, the screen
	opens on it, on the kingdom map at the next map to clear."""
	if str(area_now.call()) != TOWN or not bool(shows_crownfall.call()) or _crown_busy:
		paint()
		return
	_crown_busy = true
	_crown_said = "Asking the server..."
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter",
		{"game": CROWN_GAME, "slot": int(CharacterData.active_character_index)}, 6.0)
	_crown_busy = false
	_crown_said = ""
	if not is_instance_valid(self):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		crown_left = maxi(0, int(data.get("plays_left", 0)))
		crown_progress = maxi(crown_progress, int(data.get("progress", 0)))
		if crown_left <= 0:
			forget_wait(CROWN_GAME)
		close()
		open_crownfall.call(int(data["run"]), data.get("pays", {}) if data.get("pays") is Dictionary else {},
			crown_progress)
		return
	if int(res.get("status", 0)) == 409:
		crown_left = 0
		crown_wait = maxi(0, int(data.get("ready_in", 0)))
		_crown_said_msec = Time.get_ticks_msec()
		_crown_known = true
		note_wait(CROWN_GAME, crown_wait)
	else:
		_crown_said = UNREACHABLE
	paint()


func _paint_testing() -> void:
	testing_box.visible = bool(shows_testing.call())
	var can_go: bool = false
	if inside_endless():
		testing_status.text = "You are here - Leave is on the Endless above." if GameState.testing_ground \
			else "Leave the Endless first."
	elif bool(in_party.call()):
		testing_status.text = "Leave your party first - a party shares its arena."
	else:
		testing_status.text = "Ready - no run, no timer, nothing counts"
		can_go = true
	testing_status.add_theme_color_override("font_color", COLOUR_READY if can_go else COLOUR_HINT)
	testing_go.disabled = not can_go
	testing_go.tooltip_text = "Down to the Endless's arena, empty - the GM panel's Spawn and the horde buttons fill it"


func _on_testing_go() -> void:
	"""Go: the Endless's map with no run (GameState.testing_ground). No day is
	spent - the server is not asked."""
	if not bool(shows_testing.call()) or inside_endless() or bool(in_party.call()):
		paint()
		return
	GameState.testing_ground = true
	travel.call(GAME, ENTRANCE)
	close()


func _paint_pinball() -> void:
	pinball_box.visible = bool(shows_pinball.call())
	var in_town: bool = str(area_now.call()) == TOWN
	@warning_ignore("integer_division")
	var wait_left: int = maxi(0, pin_wait - int((Time.get_ticks_msec() - _pin_said_msec) / 1000)) \
		if _pin_known else 0
	var none_left: bool = _pin_known and pin_left <= 0 and wait_left > 0
	var best_words: String = "  ·  best %s" % score_words(pin_best) if pin_best > 0 else ""
	if _pin_said != "":
		pinball_status.text = _pin_said
	elif not in_town:
		pinball_status.text = FROM_TOWN
	elif none_left:
		pinball_status.text = "Practice - paid games %s%s" % [wait_text(wait_left).to_lower(), best_words]
	elif _pin_known:
		pinball_status.text = "Ready - %d of 3 games left today%s" % [pin_left, best_words]
	else:
		pinball_status.text = "Ready"
	var go_on: bool = in_town and not _pin_busy
	pinball_status.add_theme_color_override("font_color", COLOUR_READY if go_on and not none_left
		else (COLOUR_WAIT if none_left else COLOUR_HINT))
	pinball_go.disabled = not go_on
	pinball_go.tooltip_text = ("Play the Beholder's Table - your character waits in town" if not none_left
		else "Practice on the Beholder's Table - it pays nothing") if in_town else "Go back to town first"


func _on_pinball_go() -> void:
	"""Go: the server asked for one of the day's three paid games first; let
	in, the table opens on it. With none left - said now, or by the server -
	it opens as practice."""
	if not bool(shows_pinball.call()) or str(area_now.call()) != TOWN or _pin_busy:
		paint()
		return
	@warning_ignore("integer_division")
	var wait_left: int = maxi(0, pin_wait - int((Time.get_ticks_msec() - _pin_said_msec) / 1000)) \
		if _pin_known else 0
	if _pin_known and pin_left <= 0 and wait_left > 0:
		await _open_table(0, {}, pin_best)
		return
	_pin_busy = true
	_pin_said = "Asking the server..."
	paint()
	var res: Dictionary = await enter_request.call("/api/minigames/enter",
		{"game": PIN_GAME, "slot": int(CharacterData.active_character_index)}, 6.0)
	_pin_busy = false
	_pin_said = ""
	if not is_instance_valid(self):
		return
	var data: Dictionary = res.get("data", {}) if res.get("data") is Dictionary else {}
	if res.get("ok", false) and data.has("run"):
		pin_left = maxi(0, int(data.get("plays_left", 0)))
		pin_best = maxi(pin_best, int(data.get("best_score", 0)))
		_pin_known = true
		pin_wait = maxi(0, int(data.get("ready_in", 0)))
		_pin_said_msec = Time.get_ticks_msec()
		await _open_table(int(data["run"]), data.get("pays", {}) if data.get("pays") is Dictionary else {}, pin_best)
		return
	if int(res.get("status", 0)) == 409:
		pin_left = 0
		pin_wait = maxi(0, int(data.get("ready_in", 0)))
		_pin_said_msec = Time.get_ticks_msec()
		_pin_known = true
		await _open_table(0, {}, pin_best)
		return
	_pin_said = UNREACHABLE
	paint()


func _open_table(run_id: int, what_it_pays: Dictionary, best_known: int) -> void:
	"""SAID FIRST (0.168.2): the tile says OPENING and is drawn before the
	table's screen is made, and Go cannot be pressed twice meanwhile. Since
	0.168.3 the screen is light and opens at once on its own loading cover,
	which builds the table a step a frame (pinballscreen.gd)."""
	_pin_busy = true
	_pin_said = OPENING
	paint()
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	_pin_busy = false
	_pin_said = ""
	close()
	open_pinball.call(run_id, what_it_pays, best_known)


func _open_pinball(run_id: int = 0, what_it_pays: Dictionary = {}, best_known: int = 0) -> void:
	(load("res://src/world/pinball/pinballscreen.gd") as GDScript).call("open", get_tree(), hud, run_id,
		what_it_pays, best_known)


func _shows_cloth() -> bool:
	return true


func _shows_crownfall() -> bool:
	return bool(Api.is_owner)


func _open_crownfall(run_id: int = 0, what_it_pays: Dictionary = {}, how_far: int = 0) -> void:
	(load("res://src/world/crownfall/crownfallscreen.gd") as GDScript).call("open", get_tree(), hud, run_id,
		what_it_pays, how_far)


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
