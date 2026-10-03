# lootbag.gd — world-placed loot container dropped by a slain enemy.
# sits on the ground; the player walks up and presses interact to OPEN a
# draggable panel (lootbaginventory) showing the contents. this script owns
# the world-side state: ownership, the pet beam, and despawn timing.
#
# THE CONTENTS HERE ARE A PICTURE. THE BAG LIVES ON THE SERVER.
# -------------------------------------------------------------
# This node used to BE the bag: it held the items, handed them over on pickup,
# and the next save simply told the server what the player was now carrying. The
# server rolled a potion and had no idea whether you took it, left it, or
# invented forty more — which is why `gold` sat on the client-asserted list.
#
# Now /api/combat/kill stores the roll in loot_bags / loot_bag_items and returns
# a bag_id. This node renders a COPY of those rows, and taking anything out is a
# request against them (see lootbaginventory.gd). _contents is kept only so the
# panel can be re-opened without another round trip.
#
# THE INDEX OF EACH ENTRY IS THE SERVER'S POSITION. That is why it is a
# fixed-length array with null in the taken cells rather than a list that
# compacts: "take cell 2" has to mean the same cell on both sides, and a list
# that closed its gaps would start meaning a different one the moment anything
# was taken out of the middle.
#
# An empty _bag_id means the server never registered this bag. That should not
# happen — Combat only spawns a node when the kill response carried an id — and
# if it does, the panel refuses to take rather than falling back to handing
# items over locally. A client that can produce loot by making a request fail is
# the exploit this whole change exists to close.
#
# lifecycle:
# - spawned by Combat on a kill via set_bag_id / set_contents / set_owner_player
#   / set_has_pet
# - beam shows immediately if the bag holds a pet (rare drop signal)
# - a mythic (set_mythic, from the kill answer) glows far bigger and stays on
#   the ground for MYTHIC_BAG_DESPAWN_SECONDS instead of 45
# - interact (killer only) → hud.open_lootbag(self, player) shows the panel
# - the panel mirrors what is left back via set_contents as items are taken, so
#   re-opening shows the right thing without asking the server again
# - despawn: immediately when emptied (despawn_now), or after despawn_seconds
#   if items remain (leftovers are lost — "loot it or lose it")
# - NEW: walking out of range while the panel is open closes it automatically,
#   via player_left_range signal (see AREA SIGNAL HANDLERS below). the bag
#   itself doesn't know how to close the panel (it has no reference to it) —
#   it just announces "player left" and lootbaginventory.gd, which DOES hold
#   a reference to this bag while open, listens and closes itself.
#
# anti-abuse: killer-owned (only the killer can open) + timed despawn (bags
# can't persist and be arranged into shapes), the Tibia-griefing fix.
extends Area2D


# =============================================================================
# SIGNALS
# =============================================================================

# emitted when the player who has this bag's panel open walks out of range.
# only fires if the bag was actually open (_is_open) — a different player
# wandering past a bag they never opened shouldn't trigger anything.
signal player_left_range()


# =============================================================================
# CONSTANTS
# =============================================================================

# interaction blocked briefly after spawn so a bag dropping under the player
# doesn't instantly open from a held interact key.
const SPAWN_GRACE_PERIOD := 0.5


# =============================================================================
# STATE
# =============================================================================

# The server's id for this bag. Everything the panel does goes through it.
var _bag_id: String = ""

# A COPY of what the server's rows held when this bag was spawned, position-
# aligned: index == the server's position, null where a cell has been taken.
var _contents: Array = []

var _owner_player: Node = null
var _player_nearby: Node = null
var _has_pet: bool = false
# A DEADLINE, NOT A COUNTDOWN.
#
# It used to be a float ticked down in _process(), which meant every bag on the
# ground had to run a frame callback purely to subtract from a number - and
# because the countdown had to keep running whether or not anyone was near, the
# bag could never turn processing off. A deadline needs nothing to tick it, so
# _process() can be switched off entirely until a player is actually standing
# in range. See _set_listening().
var _spawn_deadline_msec: int = 0
var _is_open: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var anim: AnimatedSprite2D = $animatedsprite2d
@onready var despawn_timer: Timer = $despawntimer

# THE RARE-DROP GLOW, built in code by _build_glow(). It replaced "petbeam", a
# flat five-pixel Line2D 149 pixels tall that only ever lit for pets and read as
# a stick poking out of the sack. Now any bag holding an epic or legendary item
# glows in that rarity's colour: a soft pillar, a pool of light on the ground,
# and a few motes drifting up, pulsing gently.
var _glow: Node2D = null
var _glow_tween: Tween = null
var _glow_tier: int = 0

const GLOW_PILLAR_HEIGHT := 56
const GLOW_PILLAR_WIDTH := 12
const GLOW_CORE_WIDTH := 4
const GLOW_POOL_SIZE := Vector2i(34, 12)

# A MYTHIC IN THE BAG, set by Combat when the kill answer names one. The glow is
# already red for the tier. This makes it the loudest thing on screen: the
# pillar half as wide again and more than twice as tall, three times the motes,
# a burst of sparks as it lands, and MYTHIC_BAG_DESPAWN_SECONDS on the ground
# instead of 45. It lasts only while the mythic is still in the bag.
var _mythic: bool = false
const MYTHIC_GLOW_SCALE := Vector2(1.5, 2.4)
const MYTHIC_MOTES := 30
const MYTHIC_PILLAR_BRIGHTNESS := Color(1.25, 1.25, 1.25, 1.9)


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation("idle"):
		anim.play("idle")

	_spawn_deadline_msec = Time.get_ticks_msec() + int(SPAWN_GRACE_PERIOD * 1000.0)

	# NOTHING TO DO UNTIL SOMEONE WALKS UP. The only thing _process() does is
	# poll one key, which cannot matter to a bag with no player in range - and
	# a pile of bags each polling it every frame is a pile of frame callbacks
	# doing nothing. _on_body_entered/_on_body_exited turn it back on.
	set_process(false)

	# So bags can see each other - _is_nearest_candidate() needs to enumerate
	# the others to decide which one a press belongs to.
	add_to_group(&"lootbags")

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if despawn_timer != null:
		despawn_timer.one_shot = true
		despawn_timer.wait_time = despawn_seconds()
		if not despawn_timer.timeout.is_connected(_on_despawn_timeout):
			despawn_timer.timeout.connect(_on_despawn_timeout)
		despawn_timer.start()

	_apply_glow()


func _process(_delta: float) -> void:
	# Only runs while a player is standing in range - see _set_listening().
	if _in_spawn_grace():
		return

	if _is_open:
		return
	if _player_nearby == null:
		return
	if not Input.is_action_just_pressed("interact"):
		return

	# NEAREST BAG WINS, not whichever one Godot calls _process() on first.
	#
	# Input.is_action_just_pressed() is a global state query, not a consumable
	# event - every node that polls it on the press frame sees true. Bags from
	# several kills land on the same corpse pile, so the player stands in more
	# than one radius at once and a single press ran _try_open() on all of them.
	# Without this gate the bag you actually got was decided by scene tree
	# order, so pressing interact between two bags could open the far one.
	if not _is_nearest_candidate():
		return

	# Belt and braces for two bags at exactly equal distance: whichever claims
	# the frame first is the only one that acts.
	var frame: int = Engine.get_process_frames()
	if _press_claimed_frame == frame:
		return
	_press_claimed_frame = frame

	_try_open()


# Shared by every bag. See the comment in _process() for what it guards.
#
# The damage from the old behaviour was not the duplicate log lines. Every bag
# that opened also PAUSED ITS DESPAWN TIMER, and only the one whose panel the
# HUD actually showed ever received notify_panel_closed() to unpause it. The
# others sat un-openable until the player walked out of range, and never
# despawned at all - "loot it or lose it" quietly stopped applying to them.
static var _press_claimed_frame: int = -1


# True when no other bag this same player is standing in sits closer.
func _is_nearest_candidate() -> bool:
	var my_distance: float = global_position.distance_squared_to(_player_nearby.global_position)

	for other in get_tree().get_nodes_in_group(&"lootbags"):
		if other == self or not is_instance_valid(other):
			continue
		var bag := other as Node2D
		if bag == null:
			continue

		# Only bags THIS player is standing in compete. One across the room is
		# not a candidate however the distance maths comes out.
		if bag.get("_player_nearby") != _player_nearby:
			continue
		if bool(bag.get("_is_open")):
			continue

		# A bag still inside its spawn grace period cannot be opened yet, so
		# letting it compete would just block the bag the player meant.
		if bag.has_method("_in_spawn_grace") and bag.call("_in_spawn_grace"):
			continue

		if bag.global_position.distance_squared_to(_player_nearby.global_position) < my_distance:
			return false

	return true


# =============================================================================
# SETUP — called by Combat when the kill response lands
# =============================================================================

func set_bag_id(bag_id: String) -> void:
	_bag_id = bag_id


func get_bag_id() -> String:
	return _bag_id


func set_contents(contents: Array) -> void:
	# Position-aligned, nulls included. The panel writes back through here too,
	# and it deliberately hands over an array that is still the full length.
	_contents = contents
	_apply_glow()


func get_contents() -> Array:
	return _contents


func set_owner_player(player: Node) -> void:
	_owner_player = player


func set_has_pet(has_pet: bool) -> void:
	_has_pet = has_pet
	_apply_glow()


func set_mythic(on: bool) -> void:
	"""The kill answer named a mythic, and it is in this bag. Called once, by
	Combat, after set_contents()."""
	_mythic = on
	# THE TIMER WAS ALREADY STARTED, at 45 seconds, by _ready(): Combat adds
	# the bag to the world before it hands over what is in it. Restarted here
	# for the longer time. start() leaves a pause the open panel put on it.
	if despawn_timer != null and is_inside_tree():
		despawn_timer.start(despawn_seconds())
	_apply_glow()
	if on and is_inside_tree():
		_burst_sparks()


func is_mythic() -> bool:
	"""True while a mythic is still in this bag. Taking it out ends the show."""
	return _mythic and rare_tier_of(_contents, false) >= GameConstants.MYTHIC_TIER


func despawn_seconds() -> float:
	return GameConstants.MYTHIC_BAG_DESPAWN_SECONDS if _mythic else GameConstants.LOOT_BAG_DESPAWN_SECONDS


static func rare_tier_of(contents: Array, has_pet: bool) -> int:
	"""The rarest thing in the bag, as a tier. A pet counts as legendary.

	Currency is left out: a heap of coins rolls a tier for its SIZE, not for
	how rare it is, and a big pile of gold glowing like an ember sword would
	teach the player the glow means nothing."""
	var best: int = 5 if has_pet else 0
	for entry in contents:
		if not (entry is Dictionary):
			continue
		var data: ItemData = ItemRegistry.get_item(str(entry.get("item_id", "")))
		if data == null or data.type == ItemData.Type.CURRENCY:
			continue
		best = maxi(best, int(data.tier))
	return best


func glow_tier() -> int:
	"""The tier the bag is glowing for, or 0 when it is not glowing."""
	return _glow_tier if _glow != null and _glow.visible else 0


func _apply_glow() -> void:
	var tier: int = rare_tier_of(_contents, _has_pet)
	var lit: bool = tier >= GameConstants.RARE_GLOW_MIN_TIER
	if not lit:
		_glow_tier = 0
		if _glow != null:
			_glow.visible = false
		if _glow_tween != null:
			_glow_tween.kill()
			_glow_tween = null
		return
	if _glow == null:
		_build_glow()
	_glow_tier = tier
	var colour: Color = GameConstants.rarity_colour(tier)
	for part in _glow.get_children():
		if part is Sprite2D:
			var tex: GradientTexture2D = (part as Sprite2D).texture
			var g: Gradient = tex.gradient
			g.set_color(0, Color(colour, g.get_color(0).a))
			g.set_color(1, Color(colour, 0.0))
		elif part is CPUParticles2D:
			var ramp: Gradient = (part as CPUParticles2D).color_ramp
			ramp.set_color(0, Color(colour, 0.9))
			ramp.set_color(1, Color(colour, 0.0))
	_glow.visible = true
	# The pillar grows from the sack upward, and the pool spreads on the ground,
	# so each part is scaled on its own rather than the whole glow from its
	# middle, which would push the pool into the grass.
	var mythic_now: bool = is_mythic()
	var tall: Vector2 = MYTHIC_GLOW_SCALE if mythic_now else Vector2.ONE
	for part_name in ["pillar", "core"]:
		var part: Sprite2D = _glow.get_node_or_null(part_name) as Sprite2D
		if part != null:
			part.scale = tall
			part.position.y = -GLOW_PILLAR_HEIGHT * tall.y / 2.0 + 2
			# Brighter as well as bigger: the ordinary pillar is drawn soft
			# on purpose, and at mythic size it read as faint on dark ground.
			part.self_modulate = MYTHIC_PILLAR_BRIGHTNESS if mythic_now else Color.WHITE
	var pool: Sprite2D = _glow.get_node_or_null("pool") as Sprite2D
	if pool != null:
		pool.scale = Vector2(tall.x, tall.x)
	var motes: CPUParticles2D = _glow.get_node_or_null("motes") as CPUParticles2D
	if motes != null:
		var wanted: int = MYTHIC_MOTES if mythic_now else 10
		if motes.amount != wanted:
			motes.amount = wanted
		motes.initial_velocity_max = 44.0 if mythic_now else 24.0
	if _glow_tween == null and is_inside_tree():
		_glow_tween = create_tween().set_loops()
		_glow_tween.tween_property(_glow, "modulate:a", 0.65, 0.9).set_trans(Tween.TRANS_SINE)
		_glow_tween.tween_property(_glow, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)


func _glow_sprite(size: Vector2i, top_alpha: float, radial: bool) -> Sprite2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, top_alpha))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = size.x
	tex.height = size.y
	if radial:
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
	else:
		# Bright at the sack, gone at the top.
		tex.fill_from = Vector2(0.5, 1.0)
		tex.fill_to = Vector2(0.5, 0.0)
	# ORDINARY BLENDING, NOT ADDITIVE. Added light washes toward white over
	# anything bright: an ember glow over water came out pale cyan. Mixed, it
	# stays the rarity's own colour on grass, stone and water alike.
	var sprite := Sprite2D.new()
	sprite.texture = tex
	return sprite


func _build_glow() -> void:
	_glow = Node2D.new()
	_glow.name = "rareglow"
	_glow.show_behind_parent = true
	add_child(_glow)

	var pool: Sprite2D = _glow_sprite(GLOW_POOL_SIZE, 0.6, true)
	pool.name = "pool"
	pool.position = Vector2(0, 4)
	_glow.add_child(pool)

	var pillar: Sprite2D = _glow_sprite(Vector2i(GLOW_PILLAR_WIDTH, GLOW_PILLAR_HEIGHT), 0.4, false)
	pillar.name = "pillar"
	pillar.position = Vector2(0, -GLOW_PILLAR_HEIGHT / 2.0 + 2)
	_glow.add_child(pillar)

	var core: Sprite2D = _glow_sprite(Vector2i(GLOW_CORE_WIDTH, GLOW_PILLAR_HEIGHT), 0.8, false)
	core.name = "core"
	core.position = pillar.position
	_glow.add_child(core)

	var motes := CPUParticles2D.new()
	motes.name = "motes"
	motes.amount = 10
	motes.lifetime = 1.6
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(5, 2)
	motes.direction = Vector2.UP
	motes.spread = 12.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 14.0
	motes.initial_velocity_max = 24.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	motes.color_ramp = ramp
	_glow.add_child(motes)


func _burst_sparks() -> void:
	# ONE BURST AS THE BAG LANDS, red to white, thrown up and out and falling
	# back. One shot, freed when it is done. Not part of the glow, so taking
	# the mythic out of the bag does not cut it short.
	var sparks := CPUParticles2D.new()
	sparks.name = "mythicsparks"
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.amount = 48
	sparks.lifetime = 1.1
	sparks.position = Vector2(0, -6)
	sparks.direction = Vector2.UP
	sparks.spread = 70.0
	sparks.gravity = Vector2(0, 160)
	sparks.initial_velocity_min = 60.0
	sparks.initial_velocity_max = 130.0
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 2.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.85, 1.0))
	ramp.set_color(1, Color(GameConstants.rarity_colour(GameConstants.MYTHIC_TIER), 0.0))
	sparks.color_ramp = ramp
	sparks.finished.connect(sparks.queue_free)
	add_child(sparks)
	sparks.emitting = true


# =============================================================================
# OPEN
# =============================================================================

func _try_open() -> void:
	# ownership gate — only the killer can open. others are ignored silently.
	if _owner_player != null and _player_nearby != _owner_player:
		# a normal, expected outcome — somebody walked onto a bag that is not
		# theirs. The comment above already says "ignored silently"; the print
		# made it anything but.
		if OS.is_debug_build():
			print("[LOOT] bag not owned by this player — ignoring")
		return

	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("open_lootbag"):
		push_warning("LootBag: HUD has no open_lootbag() — cannot open panel")
		return

	_is_open = true

	# NEW: pause the despawn countdown while the panel is actively being
	# viewed — fixes "bag disappears while I'm still looking at it."
	# resumes (with whatever time was remaining) via notify_panel_closed()
	# once the panel actually closes.
	if despawn_timer != null and not despawn_timer.is_stopped():
		despawn_timer.paused = true

	if OS.is_debug_build():
		var held: int = 0
		for entry in _contents:
			if entry is Dictionary and str(entry.get("item_id", "")) != "":
				held += 1
		print("[LOOT] opening bag %s with %d item(s)" % [_bag_id, held])
	# Non-positional. You are standing on it, and the panel opening is an event
	# about you rather than about the world.
	Audio.play("bag_open")

	hud.open_lootbag(self, _player_nearby)


func notify_panel_closed() -> void:
	# NEW: called by lootbaginventory.gd whenever ITS panel closes, for any
	# reason — X button, walked away, or emptied. this is a second entry
	# point alongside _on_body_exited() below, because closing via the X
	# button while the player is STILL standing in range never triggers
	# body_exited at all — without this, _is_open would stay stuck true
	# forever in that case, silently blocking the bag from ever being
	# re-opened. also resumes the despawn countdown that _try_open() paused.
	_is_open = false
	if despawn_timer != null and not despawn_timer.is_stopped():
		despawn_timer.paused = false


# =============================================================================
# DESPAWN
# =============================================================================

func despawn_now() -> void:
	queue_free()


func _on_despawn_timeout() -> void:
	queue_free()


# =============================================================================
# AREA SIGNAL HANDLERS
# =============================================================================

func _in_spawn_grace() -> bool:
	# Blocks the interact key for a moment after the bag lands, so a bag
	# dropping under a player who is holding interact does not open instantly.
	return Time.get_ticks_msec() < _spawn_deadline_msec


func _set_listening(listening: bool) -> void:
	# The bag's whole per-frame cost is polling one key. A bag nobody is
	# standing on cannot act on that key, so it should not be asking.
	#
	# Worth being clear about the size of this: it is a handful of early
	# returns per bag per frame, not a bottleneck anybody would find in a
	# profile. It is here because a node that provably cannot do anything
	# should not be scheduled, and because bags accumulate - the despawn is
	# 45 seconds now, and a long fight leaves a lot of them lying around.
	set_process(listening)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = body
		_set_listening(true)


func _on_body_exited(body: Node) -> void:
	if body != _player_nearby:
		return
	_player_nearby = null
	_set_listening(false)

	# NEW: only emit if the bag was actually open when the player left —
	# otherwise a player who never opened this bag walking away would fire
	# a pointless signal with nothing listening.
	var was_open := _is_open
	_is_open = false

	# RESUME THE COUNTDOWN _try_open() PAUSED.
	#
	# notify_panel_closed() does this too, but it only ever reaches the bag
	# whose panel the HUD is showing. Any bag that set _is_open without getting
	# a panel stayed paused forever and never despawned. The nearest-wins gate
	# in _process() should mean that no longer happens, but a despawn timer that
	# can leak into never firing is worth closing from both ends.
	if despawn_timer != null and not despawn_timer.is_stopped():
		despawn_timer.paused = false

	if was_open:
		player_left_range.emit()
