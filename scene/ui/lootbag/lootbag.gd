# lootbag.gd — world-placed loot container dropped by a slain enemy.
# sits on the ground; the player walks up and presses interact to OPEN a
# draggable panel (lootbaginventory) showing the contents. this script owns
# the world-side state: contents, ownership, the pet beam, and despawn timing.
#
# lifecycle:
# - spawned by baseenemy on death via set_contents / set_owner_player / set_has_pet
# - beam shows immediately if the bag holds a pet (rare drop signal)
# - interact (killer only) → hud.open_lootbag(self, player) shows the panel
# - the panel syncs remaining contents back via set_contents as items are taken
# - despawn: immediately when emptied (despawn_now), or after despawn_seconds
#   if items remain (leftovers are lost — "loot it or lose it")
#
# anti-abuse: killer-owned (only the killer can open) + timed despawn (bags
# can't persist and be arranged into shapes), the Tibia-griefing fix.
extends Area2D


# =============================================================================
# CONSTANTS
# =============================================================================

# interaction blocked briefly after spawn so a bag dropping under the player
# doesn't instantly open from a held interact key.
const SPAWN_GRACE_PERIOD := 0.5


# =============================================================================
# STATE
# =============================================================================

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
# SETUP — called by the spawning enemy
# =============================================================================

func set_contents(contents: Array) -> void:
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
	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG._try_open called | is_open=%s | owner=%s | nearby=%s | contents_count=%d" % [
		_is_open, _owner_player, _player_nearby, _contents.size()
	])
	# === END DIAGNOSTIC ===

	# ownership gate — only the killer can open. others are ignored silently.
	if _owner_player != null and _player_nearby != _owner_player:
		print("LOOTBAG: ownership check failed, ignoring")
		return

	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("open_lootbag"):
		push_warning("LootBag: HUD has no open_lootbag() — cannot open panel")
		return

	_is_open = true
	print("LOOTBAG: calling hud.open_lootbag with %d contents" % _contents.size())
	hud.open_lootbag(self, _player_nearby)


# =============================================================================
# DESPAWN
# =============================================================================

func despawn_now() -> void:
	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG.despawn_now CALLED — stack follows:")
	print(get_stack())
	# === END DIAGNOSTIC ===
	queue_free()


func _on_despawn_timeout() -> void:
	# === DIAGNOSTIC — remove after fixing ===
	print("LOOTBAG._on_despawn_timeout CALLED (timer expired after %f seconds)" % GameConstants.LOOT_BAG_DESPAWN_SECONDS)
	# === END DIAGNOSTIC ===
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
	_is_open = false
