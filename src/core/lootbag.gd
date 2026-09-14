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
var _spawn_timer: float = 0.0
var _is_open: bool = false


# =============================================================================
# NODE REFERENCES
# =============================================================================

@onready var anim: AnimatedSprite2D = $animatedsprite2d
@onready var despawn_timer: Timer = $despawntimer
@onready var pet_beam: Node = get_node_or_null("petbeam")


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation("idle"):
		anim.play("idle")

	_spawn_timer = SPAWN_GRACE_PERIOD

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if despawn_timer != null:
		despawn_timer.one_shot = true
		despawn_timer.wait_time = GameConstants.LOOT_BAG_DESPAWN_SECONDS
		if not despawn_timer.timeout.is_connected(_on_despawn_timeout):
			despawn_timer.timeout.connect(_on_despawn_timeout)
		despawn_timer.start()

	_apply_beam_state()


func _process(delta: float) -> void:
	if _spawn_timer > 0.0:
		_spawn_timer -= delta
		return

	if _is_open:
		return
	if _player_nearby == null:
		return
	if not Input.is_action_just_pressed("interact"):
		return

	_try_open()


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


func get_contents() -> Array:
	return _contents


func set_owner_player(player: Node) -> void:
	_owner_player = player


func set_has_pet(has_pet: bool) -> void:
	_has_pet = has_pet
	_apply_beam_state()


func _apply_beam_state() -> void:
	if pet_beam == null:
		return
	if "visible" in pet_beam:
		pet_beam.visible = _has_pet
	if pet_beam is GPUParticles2D:
		pet_beam.emitting = _has_pet
	elif pet_beam is CPUParticles2D:
		pet_beam.emitting = _has_pet


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

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = body


func _on_body_exited(body: Node) -> void:
	if body != _player_nearby:
		return
	_player_nearby = null

	# NEW: only emit if the bag was actually open when the player left —
	# otherwise a player who never opened this bag walking away would fire
	# a pointless signal with nothing listening.
	var was_open := _is_open
	_is_open = false
	if was_open:
		player_left_range.emit()
