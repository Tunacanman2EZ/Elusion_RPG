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
const FLOAT_DISTANCE := 20.0
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
@export var ripple_color: Color = Color(0.85, 0.95, 1.0, 0.45)

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


func _process(delta: float) -> void:
	# BEFORE THE GRACE PERIOD RETURNS. The rings are not an interaction, so
	# there is no reason for the water to sit dead for the first second after
	# the map loads — which is exactly when the player is looking at it.
	_idle_phase += delta
	_near = move_toward(_near, 1.0 if player_in_range != null else 0.0,
		delta * IDLE_FADE_SPEED)
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
		return

	if _bait_count() <= 0:
		cast_failed.emit("You need worms for bait.")
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


func _fail(reason: String) -> void:
	cast_failed.emit(reason)
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

	caught.emit(
		str(data.get("item_id", "")),
		int(data.get("quantity", 0)),
		bool(data.get("levelled_up", false)))

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
		if stack == null:
			continue

		# SUFFIX FIRST, THEN THE LOOKUP, and the order is not cosmetic:
		# ItemRegistry.get_item() push_warning()s on an id it does not know and
		# hands back a fallback item. Asking it about every potion in the bag on
		# every cast would either fill the log with warnings or, worse, score the
		# fallback's tier as a rod.
		if not stack.item_id.ends_with("fishingrod"):
			continue
		if not ItemRegistry.has_item(stack.item_id):
			continue

		var data: ItemData = ItemRegistry.get_item(stack.item_id)
		if data != null:
			best = maxi(best, data.tier)
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
	if _state == State.IDLE or _state == State.SPENT:
		_draw_idle()
		return

	var dir: Vector2 = cast_direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var at: Vector2 = dir * FLOAT_DISTANCE

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
	var bob: Vector2 = Vector2(0.0, sin(_bob_phase) * BOB_HEIGHT)
	var ripple: Color = ripple_color
	ripple.a = ripple_color.a * (0.55 + 0.45 * absf(cos(_bob_phase)))
	draw_arc(at + bob, RIPPLE_RADIUS, 0.0, TAU, 20, ripple, 1.0, true)
	draw_circle(at + bob, FLOAT_RADIUS, float_color)


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

	if _near <= 0.01:
		return

	# IN RANGE, SO SHOW WHERE THE FLOAT WILL LAND. This is the only cue the
	# player gets about cast_direction, which is a per-spot export and is
	# otherwise invisible until they have already committed to a cast. It also
	# doubles as the "you can fish here now" confirmation.
	var dir: Vector2 = cast_direction.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP

	var target: Color = float_color
	target.a = float_color.a * _near * 0.55
	draw_arc(dir * FLOAT_DISTANCE, FLOAT_RADIUS + 1.5, 0.0, TAU, 16, target, 1.0, true)
