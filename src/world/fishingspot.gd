# fishingspot.gd — a patch of water you can fish. Walk up, press interact to
# cast, wait for the bite, press again to land it.
#
# NO ART OF ITS OWN, AND THAT IS THE DESIGN. The water is already drawn by the
# tilemap; this is the interaction sitting on top of it, so one scene works over
# any water you paint without needing a variant per tileset. Everything the
# player sees while fishing — the float, the ripple, the bite — is drawn in
# _draw() from the state machine below, which means it always matches the timing
# exactly rather than being an animation that has to be kept in sync with it.
#
#
# THE SERVER DECIDES WHAT WAS CAUGHT. THIS DOES NOT.
#
# docs/inventoryauthority.md in the API project names this endpoint specifically:
#
#     POST /api/fishing/catch decides what was caught. The client sends that it
#     fished, not what it got — a client that names its own catch is a client
#     that catches whatever it likes.
#
# So the request carries the slot and nothing else. Not the fish, not the
# quantity, not the rod, not the fishing level — every one of those is a thing a
# patched client would simply assert. The rod check and the level check happen on
# the server against rows it owns; the copies read here are for the UI only, to
# refuse a cast early and say why rather than firing a request that comes back
# 403. A player who patches out that early refusal gets the same 403.
#
#
# THE TIMING WINDOW IS THE ONLY THING THIS SCRIPT ACTUALLY DECIDES, and it is
# safe for it to: missing the window costs the player a catch. A client that
# patched itself a perfect hook would be cheating itself out of nothing, because
# the server rolls the same table either way. That is the test from the doc —
# could a malicious client profit by lying here? — and the answer is no, which
# is why this part is allowed to live on the client.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# Matches firepit.gd. Stops a cast firing on a key the player was already
# holding when the scene loaded.
const SPAWN_GRACE_PERIOD := 1.0

# How long the float sits before a fish takes it, in seconds. Rolled per cast so
# the player cannot count it out — a fixed wait is a rhythm you learn once and
# then stop watching.
const WAIT_MIN := 2.0
const WAIT_MAX := 6.5

# How long the player has to strike once the float goes under.
#
# THE WHOLE SKILL TEST, AND IT IS DELIBERATELY GENEROUS. 0.9s is about three
# times a comfortable human reaction, because the punishment for missing is
# losing the cast and starting again — an unforgiving window turns a calm
# activity into a chore. The tell is loud too: the float vanishes and the
# ripples stop.
const BITE_WINDOW := 0.9

# Beat between landing a fish and being allowed to cast again, so the result
# can be read before the next float goes out.
const RECAST_DELAY := 0.6

# Float geometry, in pixels from this node's origin.
const FLOAT_RADIUS := 3.0
const RIPPLE_RADIUS := 9.0
const BOB_HEIGHT := 1.5
const BOB_SPEED := 2.4


# =============================================================================
# THE IDLE TELL — how a player knows this water can be fished
# =============================================================================
# WITHOUT THIS THE SPOT IS INVISIBLE. _draw() used to render nothing until a
# cast was already running, so the only way to find a fishing spot was to walk
# onto one and press interact on the off-chance. A thing the player has to
# discover by guessing is a thing most players never discover.
#
# RINGS RISING AND FADING, not an icon floating over the water. An icon says
# "this is a game object"; rings say "something just moved under there", which
# is the same information delivered as part of the world. It also costs no art,
# which matters because the whole scene is deliberately art-free so one spot
# works over any tileset — see the header.

# Seconds for one ring to travel from the centre out to IDLE_RIPPLE_MAX.
const IDLE_RIPPLE_PERIOD := 2.4

# How many rings are in flight at once, evenly spread through the period. Two
# reads as a living surface; one reads as a blinking marker.
const IDLE_RIPPLE_COUNT := 2

const IDLE_RIPPLE_MAX := 13.0

# How visible the tell is from across the map, as a fraction of ring_color's
# alpha. Deliberately faint: it has to be findable without turning every pond
# into a christmas tree.
const IDLE_ALPHA_FAR := 0.30

# And how visible once the player is close enough to actually fish. The jump is
# the confirmation that they are in range — it replaces the "press E" prompt
# this game does not have.
const IDLE_ALPHA_NEAR := 1.0

# Seconds to fade between those two, so walking in and out reads as the water
# noticing rather than as a light switch.
const IDLE_FADE_SPEED := 4.0


# =============================================================================
# THE FISH — shapes under the surface, drawn for the same reason the rings are
# =============================================================================
# Rings say something moved. Fish say what. The rings alone were enough to find
# a spot and not enough to want to stand at one, because a ripple is ambiguous
# and a shape crossing under the water is not.
#
# DRAWN, NOT AUTHORED, and that is a constraint this file already set for
# itself — see the header: the whole scene is art-free so one spot scene works
# over any tileset, pond, river or coastline without a sprite that has to match
# the water underneath it. A silhouette obeys that where a fish sprite would
# not: it is a hole in the light, so it reads against any colour.

# How many fish circle a spot. Three is enough to look like a shoal and few
# enough that you can follow one, which is what makes you stop and watch.
const FISH_COUNT := 3

# The circuits they swim, in pixels. Spread so they cross each other's paths
# rather than running as concentric rings, which reads as a machine.
# The inner circuit has to be wider than a fish is long, or the innermost one
# turns on the spot instead of swimming — which is what 5.5 against a 7.5 body
# looked like when this was first drawn.
const FISH_ORBIT_MIN := 8.0
const FISH_ORBIT_MAX := 15.0

# Radians per second, before each fish's own variation. Slow: a fish that keeps
# pace with a ripple looks like it is being dragged.
const FISH_SPEED := 0.55

# Body size. At this scale the silhouette is about seven pixels long, which is
# the smallest a fish shape stays a fish shape rather than a dash.
const FISH_LENGTH := 7.0
const FISH_WIDTH := 2.9

# THE CIRCUIT IS SQUASHED VERTICALLY. A true circle reads as a hoop standing up
# out of the water; flattening it lays the path down onto the surface, which is
# the same trick every shadow in this game uses.
const FISH_ORBIT_SQUASH := 0.55

# How far a fish sways off its path as it swims, in pixels. This is the whole
# difference between something swimming and something orbiting.
const FISH_WAG := 0.8
const FISH_WAG_SPEED := 5.5

# Same near/far treatment as the rings: visible enough to notice from a
# distance, clearer once you are standing there.
const FISH_ALPHA_FAR := 0.20
const FISH_ALPHA_NEAR := 0.45


# =============================================================================
# THE CATCH — what `caught` looks like
# =============================================================================
# How long the fish that came out stays on screen, and how far it rises in that
# time. It is the item's own icon, so the player sees the thing that just went
# into their bag rather than a generic sparkle.
const CATCH_SHOW_SECONDS := 1.25
const CATCH_RISE := 20.0
const CATCH_ICON_SIZE := 16.0


# =============================================================================
# STATE MACHINE
# =============================================================================
# IDLE     nothing happening; interact casts
# WAITING  float is out, bobbing, fish has not taken it yet
# BITING   float is under — BITE_WINDOW seconds to press interact
# LANDING  request in flight to the server
# SPENT    just finished; RECAST_DELAY before IDLE
enum State { IDLE, WAITING, BITING, LANDING, SPENT }


# =============================================================================
# SIGNALS
# =============================================================================

# What the server said came out of the water. The HUD listens for this to put a
# notice on screen; nothing here draws text.
signal caught(item_id: String, quantity: int, levelled_up: bool)

# A cast that ended with nothing — the window was missed, or the server refused.
# reason is a short sentence already fit to show the player.
signal cast_failed(reason: String)


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# Which way the float lands relative to this node. Points at the water when the
# spot is placed on a bank, so the line does not appear to go into the ground.
@export var cast_direction: Vector2 = Vector2(0, -1)

# Drawn while a cast is in progress. Kept as exports rather than constants so a
# murky pond and a clear river can look different without a second scene.
@export var float_color: Color = Color(0.92, 0.25, 0.22, 1.0)

# How far from this node's origin the float lands, in pixels, along
# cast_direction.
#
# ZERO, AND THAT IS THE FIX FOR "IT RAISES UP WHEN I START FISHING".
#
# It was 20. The idle ripples are drawn at the origin — which is where the 22px
# interact trigger is — but every cast-state visual (the float, its ripple, the
# bite ring, the catch splash) was drawn at origin + 20px along cast_direction,
# which defaults to UP. So the marker sat on the spot until you cast and then
# jumped a whole tile north. Two positions for one object, and the one you
# aimed at was never the one that mattered.
#
# At zero the float lands on the spot: idle, cast, bite and catch all share the
# trigger's centre, and nothing moves when the state changes.
#
# PER SPOT, so a pond that genuinely wants the float thrown out from the bank
# can have it — but then the spot's own marker and its trigger are the things
# to keep together, not the float.
@export var float_distance: float = 0.0

# Whether to draw the red "your float lands here" ring while standing in range.
#
# FALSE, because it marked a point twenty pixels from the spot in the loudest
# colour on screen and the spot itself is a pale ripple. See _draw_idle() for
# the full account — briefly, the player aimed at the preview instead of the
# spot and the interact never fired.
#
# Turn it on per spot when cast_direction is something the player picked rather
# than a fixed export they cannot see.
@export var show_cast_preview: bool = false
@export var ripple_color: Color = Color(0.85, 0.95, 1.0, 0.45)

# The fish. Nearly black and slightly blue, because this is a silhouette seen
# through water rather than a fish seen in air — it is the absence of light,
# which is why it reads over any tileset without knowing what is underneath.
@export var fish_color: Color = Color(0.04, 0.10, 0.16, 1.0)

# What this spot takes as bait, one per fish landed.
#
# AN ITEM ID RATHER THAN A SUFFIX MATCH, unlike the rod check below. There is
# exactly one bait item, so naming it is honest; the rods are a ladder of five
# and matching them by name would mean editing this file to add a sixth.
#
# EXPORTED SO A SPOT CAN WANT SOMETHING ELSE. A deep-water spot taking a
# different bait is a scene property, not a new script.
@export var bait_item_id: StringName = &"fishingworm"


# =============================================================================
# STATE
# =============================================================================

var player_in_range: Node = null

var _state: State = State.IDLE
var _timer: float = 0.0
var _bob_phase: float = 0.0
var _spawn_timer: float = 0.0

# Drives the idle rings. Runs whatever the state, so the surface never freezes.
var _idle_phase: float = 0.0

# Eases between IDLE_ALPHA_FAR and IDLE_ALPHA_NEAR. 0 = nobody near, 1 = in
# range. Tracked rather than read straight off player_in_range so the change is
# a fade instead of a snap.
var _near: float = 0.0

# The catch currently being shown, if any. Set from the `caught` signal and
# counted down in _process; zero means nothing is on screen.
var _catch_icon: Texture2D = null
var _catch_tint: Color = Color.WHITE
var _catch_timer: float = 0.0
var _catch_levelled: bool = false


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_spawn_timer = SPAWN_GRACE_PERIOD

	# Everything the player sees here is drawn rather than animated, so this node
	# redraws continuously — the idle rings never stop, which is the whole point
	# of them. It is three draw_arc calls a frame and Godot skips _draw entirely
	# for a node off screen, so a map full of spots costs nothing worth counting.
	set_process(true)

	# STAGGERED PER SPOT. Two pools side by side rippling in perfect lockstep
	# read as one animation playing twice, which is the most reliable tell that
	# a world is fake. Same reasoning as firepit.gd starting its crackle loop at
	# a random offset.
	_idle_phase = randf() * IDLE_RIPPLE_PERIOD

	# LISTENING TO ITS OWN ANNOUNCEMENT, on purpose.
	#
	# `caught` already existed and nothing anywhere connected to it, so landing a
	# fish looked identical to losing one — the item appeared in the bag and the
	# water carried on rippling. The fix is not to call a draw function from
	# _land_catch(); it is to make the signal the thing that drives the visual,
	# so the announcement and the reaction cannot drift apart. If the emit ever
	# moves, or grows a condition, what the player sees moves with it.
	#
	# It also means this is now a worked example rather than a dead signal: a
	# quest, an achievement or the HUD connects to exactly the same line.
	if not caught.is_connected(_on_caught):
		caught.connect(_on_caught)


func _process(delta: float) -> void:
	# BEFORE THE GRACE PERIOD RETURNS. The rings are not an interaction, so
	# there is no reason for the water to sit dead for the first second after
	# the map loads — which is exactly when the player is looking at it.
	_idle_phase += delta
	_near = move_toward(_near, 1.0 if player_in_range != null else 0.0,
		delta * IDLE_FADE_SPEED)

	# Counted here rather than on a timer so it ticks with the same clock as the
	# rings and the fish, and so a paused tree pauses the catch with everything
	# else instead of it expiring behind a menu.
	if _catch_timer > 0.0:
		_catch_timer = maxf(_catch_timer - delta, 0.0)

	queue_redraw()

	if _spawn_timer > 0.0:
		_spawn_timer -= delta
		return

	_tick_state(delta)

	if _state == State.WAITING or _state == State.BITING:
		_bob_phase += delta * BOB_SPEED

	# LANDING waits on the server, not on a key, so it takes no input at all -
	# and a player mashing interact during the request must not queue a second
	# cast that fires the moment the first returns.
	if _state == State.LANDING or _state == State.SPENT:
		return
	if player_in_range == null:
		return
	if not Input.is_action_just_pressed("interact"):
		return

	match _state:
		State.IDLE:
			_begin_cast()
		State.WAITING:
			# Striking before the fish takes it. Costs the cast, which is the
			# only reason not to simply hold the key down.
			_fail("Too early — the float has not gone under yet.")
		State.BITING:
			_land_catch()


func _tick_state(delta: float) -> void:
	if _state == State.IDLE:
		return

	_timer -= delta
	if _timer > 0.0:
		return

	match _state:
		State.WAITING:
			# The wait ran out: something has taken it. The window opens here.
			_set_state(State.BITING, BITE_WINDOW)
		State.BITING:
			_fail("It got away.")
		State.SPENT:
			_set_state(State.IDLE, 0.0)


func _set_state(next: State, duration: float) -> void:
	_state = next
	_timer = duration
	queue_redraw()


# =============================================================================
# CASTING
# =============================================================================

func _begin_cast() -> void:
	# CHECKED HERE ONLY TO EXPLAIN THE REFUSAL. The server checks both of these
	# again against rows it owns, and its answer is the one that counts — see
	# the header. Without them the player with no rod gets a cast, a wait, a
	# bite and then a 403, which reads as the game being broken rather than as
	# them needing a rod.
	#
	# ROD FIRST, THEN BAIT, and the order is the message. Telling someone with
	# neither that they need worms sends them off to find bait for a rod they do
	# not have; telling them the rod first gets them one thing at a time in the
	# order they need it.
	if _best_rod_tier() <= 0:
		cast_failed.emit("You need a fishing rod.")
		_notify("You need a fishing rod.")
		return

	if _bait_count() <= 0:
		cast_failed.emit("You need worms for bait.")
		_notify("You need worms for bait.")
		return

	_bob_phase = 0.0
	_set_state(State.WAITING, randf_range(WAIT_MIN, WAIT_MAX))


# How much bait the player is carrying.
#
# NOT CONSUMED HERE. The worm is spent by /api/fishing/catch in the same
# transaction that grants the fish, for the reason docs/inventoryauthority.md
# gives: a client that removes its own bait is a client that can decline to.
# This count only decides whether to refuse the cast early and say why.
func _bait_count() -> int:
	var backpack: Node = _backpack()
	if backpack == null or not backpack.has_method("get_quantity_of"):
		return 0
	return int(backpack.get_quantity_of(String(bait_item_id)))


# TELLING THE PLAYER, as well as announcing it.
#
# cast_failed and caught were emitted into nothing — no .gd and no .tscn in the
# project connects either one, and this file's own header claims "the HUD
# listens for this". It did not. A player with no rod pressed interact at the
# pond and got no float, no sound and no text: indistinguishable from the key
# not being bound.
#
# The signals stay, because a quest or a tutorial is exactly the kind of thing
# that should be able to hear a catch without this script knowing about it.
# They are just no longer the ONLY thing that happens — the same "signal as
# well as the direct call" shape firepit.gd uses for cook_requested.
func _notify(message: String) -> void:
	if player_in_range != null and player_in_range.has_method("show_notice"):
		player_in_range.show_notice(message)


func _fail(reason: String) -> void:
	cast_failed.emit(reason)
	_notify(reason)
	_set_state(State.SPENT, RECAST_DELAY)


func _land_catch() -> void:
	_set_state(State.LANDING, 0.0)

	# THE REQUEST CARRIES THE SLOT AND NOTHING ELSE. Read the header before
	# adding a field to this dictionary: every extra thing named here is another
	# thing the server would have to either verify or trust.
	var res: Dictionary = await Api.post("/api/fishing/catch", {
		"slot": CharacterData.active_character_index,
	})

	# PAST AN AWAIT. This node can have been freed while the request was in
	# flight - the player walked through a ladder, the scene changed - and
	# everything below touches the tree. player.gd carries the same guard around
	# its own awaits and the same explanation.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		_fail(_refusal_text(res))
		return

	var data: Dictionary = res.get("data", {})

	# RENDERED, NOT COMPUTED. The server hands back the whole backpack as the
	# authoritative layout for the same reason /api/loot/take does: a client that
	# applied its own delta and got it wrong once would push the wrong bag on the
	# next save, and the loss would look like nothing at all.
	_apply_inventory(data.get("inventory", []))

	var caught_id: String = str(data.get("item_id", ""))
	var caught_qty: int = int(data.get("quantity", 0))

	# EVERYTHING THE PLAYER SEES HANGS OFF THIS LINE. The notice used to be
	# written out here, below the emit, which meant the signal was decorative —
	# it announced something that had already been handled. _on_caught() now
	# owns the notice, the icon, the splash and the sound, and it gets them the
	# same way any other listener would.
	caught.emit(caught_id, caught_qty, bool(data.get("levelled_up", false)))

	_set_state(State.SPENT, RECAST_DELAY)


func _refusal_text(res: Dictionary) -> String:
	# The server's own sentence when it sent one - it knows why better than this
	# does, and it is already written to be read by a player.
	var data: Dictionary = res.get("data", {})
	var message: String = str(data.get("message", ""))
	if message != "":
		return message

	match int(res.get("status", 0)):
		0:   return "Cannot reach the server."
		409: return "Your backpack is full."
		429: return "Casting too quickly."
		_:   return "The line came back empty."


func _apply_inventory(cells: Array) -> void:
	if cells.is_empty():
		return
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var container: Node = hud.find_child("inventorycontainer", true, false)
	if container != null and container.has_method("load_server_array"):
		container.load_server_array(cells)


# =============================================================================
# THE ROD
# =============================================================================

# Highest rod tier the player is carrying, or 0 for none.
#
# BY TIER, NOT BY ID. The rods are a ladder — iron 1 through ember 5 — and the
# server reads the same tier off the same exported item data to decide how deep
# the catch table goes. Matching on item_id here would mean a sixth rod needs an
# edit in this file as well as a new .tres, and the two would drift.
func _best_rod_tier() -> int:
	var container: Node = _backpack()
	if container == null or not container.has_method("get_all_stacks"):
		return 0

	var best: int = 0
	for stack in container.get_all_stacks():
		# is_valid() rather than a null check: it is `data != null and
		# quantity > 0`, and every line below reads stack.data.
		if stack == null or not stack.is_valid():
			continue

		# stack.data.item_id, NOT stack.item_id.
		#
		# ItemStack holds `data` (the ItemData) and `quantity`. It has no
		# item_id of its own — the id lives on the data. Reading it off the
		# stack raised
		#
		#   Invalid access to property or key 'item_id' on a base object of
		#   type 'Resource (ItemStack)'
		#
		# on the first cast anyone ever made while actually holding a rod. The
		# loop had run plenty of times before that and never reached this line,
		# because `continue` on an empty bag is not an error — the bug needed a
		# rod in the backpack to be reachable at all, and until the debug key
		# existed nobody had one.
		if not stack.data.item_id.ends_with("fishingrod"):
			continue

		# THE REGISTRY LOOKUP IS GONE, and removing it is a fix rather than a
		# tidy-up. It asked ItemRegistry for the ItemData that the stack was
		# already holding: has_item() then get_item() then read .tier, three
		# calls to arrive back at stack.data. The old comment here explained
		# how to order those calls so get_item() would not push_warning() on a
		# potion and hand back a fallback whose tier could be scored as a rod's.
		# None of that can happen to a value that was never looked up.
		best = maxi(best, stack.data.tier)
	return best


# The player's backpack grid, or null when it cannot be reached.
#
# One lookup shared by the rod and bait checks. The group-then-find idiom is
# copied from lootbaginventory.gd and player.gd rather than reinvented; the
# player_in_range guard stays because a spot with nobody at it has no backpack
# to ask about.
func _backpack() -> Node:
	if player_in_range == null:
		return null
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	return hud.find_child("inventorycontainer", true, false)


# =============================================================================
# DRAWING
# =============================================================================

func _draw() -> void:
	# TWO LAYERS, and the split is why this is a wrapper. _draw_state() is the
	# original function unchanged, early returns and all; the catch has to draw
	# over whatever state is showing, and a catch lands in SPENT, which returns
	# from the first branch. Adding it inside would have meant unpicking every
	# return.
	_draw_state()
	_draw_catch()


func _draw_state() -> void:
	if _state == State.IDLE or _state == State.SPENT:
		_draw_idle()
		return

	var dir: Vector2 = cast_direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var at: Vector2 = dir * float_distance

	if _state == State.BITING:
		# UNDER. The float is gone and so are the ripples, which is the tell —
		# an absence reads faster than a new shape appearing, and it cannot be
		# mistaken for the idle bob. A pulled ring marks where it went down.
		var pull: float = 1.0 - clampf(_timer / BITE_WINDOW, 0.0, 1.0)
		var ring: Color = ripple_color
		ring.a = ripple_color.a * (1.0 - pull)
		draw_arc(at, RIPPLE_RADIUS * (0.4 + pull), 0.0, TAU, 20, ring, 1.5, true)
		return

	if _state == State.LANDING:
		draw_arc(at, RIPPLE_RADIUS, 0.0, TAU, 20, ripple_color, 1.5, true)
		return

	# WAITING: the float rides up and down, with a ripple that breathes against
	# it. Nothing about this says how long is left, on purpose — a countdown
	# would let the player look away until it finished.
	#
	# The fish keep swimming through the wait. They stop at BITING, which is the
	# branch above — the existing design already uses absence as the tell there,
	# and fish vanishing the instant the float goes under says "one of them has
	# it" without a single new shape on screen.
	_draw_fish()

	var bob: Vector2 = Vector2(0.0, sin(_bob_phase) * BOB_HEIGHT)
	var ripple: Color = ripple_color
	ripple.a = ripple_color.a * (0.55 + 0.45 * absf(cos(_bob_phase)))
	draw_arc(at + bob, RIPPLE_RADIUS, 0.0, TAU, 20, ripple, 1.0, true)
	draw_circle(at + bob, FLOAT_RADIUS, float_color)


# =============================================================================
# THE FISH
# =============================================================================

func _draw_fish() -> void:
	var alpha: float = lerpf(FISH_ALPHA_FAR, FISH_ALPHA_NEAR, _near)
	if alpha <= 0.01:
		return

	var body: Color = fish_color
	body.a = fish_color.a * alpha

	for i in range(FISH_COUNT):
		# EVERY FISH GETS ITS OWN EVERYTHING, derived from its index rather than
		# randomised, so a spot looks the same every time you come back to it
		# and two spots still do not match. A shoal where all three share a
		# speed reads as one object with three parts.
		var f: float = float(i)
		var spread: float = f / float(maxi(FISH_COUNT - 1, 1))
		var orbit: float = lerpf(FISH_ORBIT_MIN, FISH_ORBIT_MAX, spread)

		# Alternating direction. Three fish all going one way is a carousel.
		var way: float = -1.0 if i % 2 == 1 else 1.0
		var rate: float = FISH_SPEED * way * (1.0 - 0.22 * spread)
		var angle: float = _idle_phase * rate + f * TAU / float(FISH_COUNT)

		var along: Vector2 = Vector2(cos(angle), sin(angle) * FISH_ORBIT_SQUASH)
		var pos: Vector2 = along * orbit

		# Heading is the tangent to the squashed circuit, not to a circle — take
		# it from the circle and the fish swims visibly sideways at the top and
		# bottom of every lap.
		var heading: Vector2 = Vector2(
			-sin(angle), cos(angle) * FISH_ORBIT_SQUASH).normalized()
		if heading == Vector2.ZERO:
			heading = Vector2.RIGHT
		heading *= way

		var side: Vector2 = Vector2(-heading.y, heading.x)

		# The sway. Offsetting the whole body across its own path is a cheap
		# stand-in for a tail, and at seven pixels it is the only one that
		# reads — an actual animated tail is two pixels moving one pixel.
		pos += side * sin(_idle_phase * FISH_WAG_SPEED + f * 2.1) * FISH_WAG

		draw_colored_polygon(_fish_points(pos, heading, side), body)


func _fish_points(pos: Vector2, heading: Vector2, side: Vector2) -> PackedVector2Array:
	# A nose, two shoulders, and a forked tail. Eight points is the fewest that
	# still says "fish" rather than "leaf" at this size, and the fork is the part
	# doing that work — drop it and the shape becomes a seed.
	var l: float = FISH_LENGTH
	var w: float = FISH_WIDTH
	return PackedVector2Array([
		pos + heading * (l * 0.50),
		pos + heading * (l * 0.10) + side * (w * 0.50),
		pos - heading * (l * 0.28) + side * (w * 0.34),
		pos - heading * (l * 0.50) + side * (w * 0.52),
		pos - heading * (l * 0.34),
		pos - heading * (l * 0.50) - side * (w * 0.52),
		pos - heading * (l * 0.28) - side * (w * 0.34),
		pos + heading * (l * 0.10) - side * (w * 0.50),
	])


# =============================================================================
# THE CATCH
# =============================================================================

func _on_caught(item_id: String, quantity: int, levelled_up: bool) -> void:
	# THE ITEM'S OWN ICON, looked up rather than passed. The signal carries an
	# id because that is what the server said and what every other listener will
	# want; resolving it to a texture is this node's business alone.
	#
	# has_item() rather than a null check on get_item(): the registry hands back
	# an error_item placeholder for an unknown id, so a plain null test passes
	# and the player gets a question mark rising out of the water.
	_catch_levelled = levelled_up
	_catch_timer = CATCH_SHOW_SECONDS
	_catch_icon = null
	_catch_tint = Color.WHITE

	# The item's display name, not its id — "rawsilverfin" is a database key and
	# the player never agreed to read one.
	var shown: String = item_id
	if item_id != "" and ItemRegistry.has_item(item_id):
		var data: ItemData = ItemRegistry.get_item(item_id)
		if data != null:
			_catch_icon = data.icon
			_catch_tint = data.icon_tint
			shown = data.display_name

	if shown != "":
		_notify("Caught %s x%d" % [shown, quantity] if quantity > 1 else "Caught %s" % shown)

	Audio.play("skill_up" if levelled_up else "item_pickup")


func _draw_catch() -> void:
	if _catch_timer <= 0.0:
		return

	# 0 at the moment it lands, 1 as it disappears.
	var t: float = 1.0 - clampf(_catch_timer / CATCH_SHOW_SECONDS, 0.0, 1.0)

	var dir: Vector2 = cast_direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var at: Vector2 = dir * float_distance

	# The splash, thrown at the moment of the catch and spent within the first
	# third of the animation — water settles faster than a held fish falls.
	if t < 0.34:
		var burst: float = t / 0.34
		var splash: Color = ripple_color
		splash.a = ripple_color.a * (1.0 - burst)
		draw_arc(at, RIPPLE_RADIUS + 14.0 * burst, 0.0, TAU, 20,
			splash, lerpf(2.0, 0.6, burst), true)

	# LEVELLING UP GETS A SECOND RING, not a different one. The catch still
	# reads as a catch; the extra ring is the part that says something else
	# happened, which is how the skill-up popup elsewhere in this game works.
	if _catch_levelled:
		var gold: Color = Color(1.0, 0.85, 0.42, 0.9 * (1.0 - t))
		draw_arc(at, 6.0 + 22.0 * t, 0.0, TAU, 24, gold, lerpf(2.0, 0.5, t), true)

	if _catch_icon == null:
		return

	# EASED OUT, so it leaves the water fast and then hangs. Linear looked like
	# the fish was being winched.
	var rise: float = CATCH_RISE * (1.0 - pow(1.0 - t, 2.0))
	var half: float = CATCH_ICON_SIZE * 0.5
	var centre: Vector2 = at + Vector2(0.0, -rise)

	var tint: Color = _catch_tint
	# Holds full opacity for the first half and then goes. Fading from the start
	# means the clearest frame of the fish is the one nobody is looking at yet.
	tint.a = _catch_tint.a * clampf((1.0 - t) * 2.0, 0.0, 1.0)

	draw_texture_rect(
		_catch_icon,
		Rect2(centre - Vector2(half, half), Vector2(CATCH_ICON_SIZE, CATCH_ICON_SIZE)),
		false,
		tint)


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = body


func _on_body_exited(body: Node) -> void:
	if body != player_in_range:
		return
	player_in_range = null

	# WALKING AWAY ENDS THE CAST, including one already in the bite window. A
	# float left bobbing on water the player has left is the kind of thing that
	# is still there when they come back an hour later. LANDING is left alone —
	# that request is already with the server and its answer has to be applied
	# wherever the player is standing by the time it returns.
	if _state == State.WAITING or _state == State.BITING:
		_set_state(State.IDLE, 0.0)
		queue_redraw()


func _draw_idle() -> void:
	# THE TELL. Rings rising out of the spot and fading as they spread, like
	# something surfacing. See the IDLE TELL block for why it is this and not an
	# icon, and why it is drawn rather than authored as art.
	var strength: float = lerpf(IDLE_ALPHA_FAR, IDLE_ALPHA_NEAR, _near)

	# FIRST, so the rings draw over them. The fish are under the surface and the
	# ripples are on it; painting them the other way round puts a fish on top of
	# the water it is supposed to be beneath.
	_draw_fish()

	for i in range(IDLE_RIPPLE_COUNT):
		# Each ring is the same animation offset by its share of the period, so
		# one is always leaving as another arrives and there is no moment where
		# the water looks switched off.
		var t: float = fposmod(
			_idle_phase / IDLE_RIPPLE_PERIOD + float(i) / float(IDLE_RIPPLE_COUNT), 1.0)

		var ring: Color = ripple_color
		# Fades out as it expands — the ring is spending its energy on getting
		# bigger. A constant-alpha ring that vanishes at full size reads as a
		# loop restarting instead.
		ring.a = ripple_color.a * strength * (1.0 - t)

		# Thins as it goes too, for the same reason.
		draw_arc(Vector2.ZERO, 2.0 + IDLE_RIPPLE_MAX * t, 0.0, TAU, 20,
			ring, lerpf(1.6, 0.6, t), true)

	if _near <= 0.01 or not show_cast_preview:
		return

	# IN RANGE, SO SHOW WHERE THE FLOAT WILL LAND. This is the only cue the
	# player gets about cast_direction, which is a per-spot export and is
	# otherwise invisible until they have already committed to a cast. It also
	# doubles as the "you can fish here now" confirmation.
	#
	# AND IT IS HALF OF WHY THE SPOT FELT MISALIGNED. It draws at
	# float_distance along cast_direction — which was a hard 20px — in a
	# saturated red, over blue water. The actual spot is at Vector2.ZERO: that
	# is where the 22px trigger is centred and where the idle ripples are drawn.
	# Red at full alpha outranks a pale ripple at 45% every time, so the eye
	# picks the preview as the target, walks to it, and the interact does not
	# fire. Two circles were drawn and only the quieter one was real.
	#
	# The other half was the same offset applied to the cast-state visuals, so
	# the marker also JUMPED 20px the moment you started fishing. float_distance
	# is 0 now and both halves are gone; this stays off as well, because a
	# preview of a direction the player did not choose is a second target on
	# screen whatever distance it sits at.
	#
	# OFF BY DEFAULT rather than deleted, because the cue is worth having once
	# the player is the one choosing where to cast.
	var dir: Vector2 = cast_direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP

	var target: Color = float_color
	target.a = float_color.a * _near * 0.55
	draw_arc(dir * float_distance, FLOAT_RADIUS + 1.5, 0.0, TAU, 16, target, 1.0, true)


# =============================================================================
# ON THE MAP
# =============================================================================
# mapscreen.gd draws a pin for everything in "map_landmarks" and asks each one
# what it is. Joined in _init rather than _ready so it does not depend on this
# script having a _ready, or on anything a _ready returns early for - and so
# the pin exists from the moment the node does.

func _init() -> void:
	add_to_group("map_landmarks")

func map_landmark() -> Dictionary:
	return {"kind": "fishing", "label": "Fishing spot"}
