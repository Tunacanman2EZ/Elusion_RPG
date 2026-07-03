# lootbag.gd — world-placed loot container dropped by a slain enemy.
# borrows bankchest's interaction grammar (walk into Area2D, press interact)
# but holds its OWN one-time contents instead of toggling a shared UI.
#
# anti-abuse design (learned from Tibia's bag-arrangement griefing):
# - KILLER-OWNED: only the player who killed the enemy can open it
# - TIMED DESPAWN: auto-removes after despawn_seconds so bags can't persist
#   and be arranged into shapes/words on the ground
#
# take mechanic (v1 — auto-transfer):
# opening the bag dumps ALL contents into the player's inventory and despawns.
# gold/lusion CURRENCY items convert to their pool via the inventory container's
# converts_currency handling. a drag-out container UI can replace this later.
#
# pet signal:
# if the bag contains a pet (set_has_pet true), a loot beam shoots up from the
# bag to visually signal the rare drop from across the screen.
#
# contents format:
# _contents is an Array of { "item_id": String, "quantity": int } dictionaries,
# set by the spawning enemy via set_contents() right after instantiation.
extends Area2D

# =============================================================================
# CONSTANTS
# =============================================================================

# interaction is blocked briefly after spawn so a bag dropping under the player
# doesn't instantly open from a held interact key (mirrors bankchest).
const SPAWN_GRACE_PERIOD := 0.5


# =============================================================================
# EXPORTED SETTINGS
# =============================================================================

# how long the bag survives before auto-despawning (anti-arrangement rule).
@export var despawn_seconds: float = 60.0


# =============================================================================
# STATE
# =============================================================================

# the rolled loot — array of { "item_id": String, "quantity": int }.
var _contents: Array = []

# the player allowed to open this bag (the killer). only this node can loot it.
var _owner_player: Node = null

# the player currently inside the detection area.
var _player_nearby: Node = null

# blocks interaction during the spawn grace window.
var _spawn_timer: float = 0.0

# guards against double-open.
var _looted: bool = false

# whether this bag holds a pet — drives the loot beam.
var _has_pet: bool = false


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

	# start the despawn countdown
	if despawn_timer != null:
		despawn_timer.one_shot = true
		despawn_timer.wait_time = despawn_seconds
		if not despawn_timer.timeout.is_connected(_on_despawn_timeout):
			despawn_timer.timeout.connect(_on_despawn_timeout)
		despawn_timer.start()

	# beam starts hidden — turned on in set_has_pet if this is a pet bag.
	# (set_has_pet may be called before OR after _ready depending on spawn
	# order, so we re-apply the beam state here too.)
	_apply_beam_state()


func _process(delta: float) -> void:
	if _spawn_timer > 0.0:
		_spawn_timer -= delta
		return

	if _looted:
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
	# receives the rolled loot from the enemy.
	_contents = contents


func set_owner_player(player: Node) -> void:
	# the killer — only this player may open the bag.
	_owner_player = player


func set_has_pet(has_pet: bool) -> void:
	# flag whether this bag holds a pet; drives the loot beam. safe to call
	# before or after _ready — _apply_beam_state is idempotent.
	_has_pet = has_pet
	_apply_beam_state()


func _apply_beam_state() -> void:
	# show the loot beam only if this bag holds a pet. null-guarded so a bag
	# without a beam node still works.
	if pet_beam == null:
		return
	if "visible" in pet_beam:
		pet_beam.visible = _has_pet
	# if the beam is a particle system, start/stop emission too
	if pet_beam is GPUParticles2D:
		pet_beam.emitting = _has_pet
	elif pet_beam is CPUParticles2D:
		pet_beam.emitting = _has_pet


# =============================================================================
# OPEN / LOOT
# =============================================================================

func _try_open() -> void:
	# ownership gate — only the killer can loot. others are ignored silently.
	if _owner_player != null and _player_nearby != _owner_player:
		return
	_loot_all_to_player(_player_nearby)


func _loot_all_to_player(player: Node) -> void:
	# auto-transfer every item into the player's inventory, then despawn.
	# CURRENCY items (gold) convert to the pool via the container's
	# converts_currency handling. uses the same add_stack path debug gives use.
	if _looted:
		return

	var container: Node = _get_inventory_container()
	if container == null:
		push_warning("LootBag: could not find inventory container — loot not collected")
		return

	for entry in _contents:
		var item_id: String = entry.get("item_id", "")
		var qty: int = entry.get("quantity", 1)
		if item_id == "":
			continue

		var data: ItemData = ItemRegistry.get_item(item_id)
		if data == null:
			continue  # unknown id — skip (registry already warned)

		var stack := ItemStack.new(data, qty)
		container.add_stack(stack)

	_looted = true

	# save after looting so picked-up items survive a crash
	if player != null and CharacterData != null:
		CharacterData.save_character_state(player)

	queue_free()


func _get_inventory_container() -> Node:
	# resolve the live inventory container through the HUD, as the debug-give
	# path does. returns null if anything's missing.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	if hud.get("inventory_screen") == null:
		return null
	return hud.inventory_screen.get_node_or_null("%inventorycontainer")


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


# =============================================================================
# DESPAWN
# =============================================================================

func _on_despawn_timeout() -> void:
	# bag expired — remove it whether or not it was looted. the anti-arrangement
	# rule: bags never persist on the ground indefinitely.
	queue_free()
