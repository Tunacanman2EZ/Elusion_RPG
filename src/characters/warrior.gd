# warrior character — fast melee fighter with 4-directional attacks
# damage flows: attack_action plays animation -> frame_changed checks contact frames
# -> active hitbox scanned for enemies -> take_damage applied (one hit per swing per enemy)
# also fires a slash wave projectile during the contact window for extended reach,
# letting warrior compete with ranged classes against electric/fire enemies.
#
# damage architecture: 'attack' is the SKILL stat (player progression, 1->99 like
# other skills). it is NOT the damage value. damage comes from base_melee_damage
# plus a scaling bonus from the attack skill. when the weapon/equipment system
# is built, base_melee_damage should be replaced by the equipped weapon's damage.
extends "res://src/characters/player.gd"

# preloaded slash wave projectile scene
const SLASHWAVE_SCENE := preload("res://scene/ui/slashwave.tscn")

# damage window — frames during which the sword's melee hit registers.
# tune these to match your warrior attack animation.
@export var contact_frame_start: int = 2
@export var contact_frame_end: int = 5

# specific frame where the slash wave spawns — usually later than the melee
# contact window, so the wave appears AFTER the visible swing extends.
@export var wave_spawn_frame: int = 6

# slash wave damage as a percentage of melee damage (0.75 = 75%).
# applied to the calculated melee damage, so slashwave scales with skill too.
@export var wave_damage_ratio: float = 0.75

# base damage for warrior's melee attack — separate from the attack skill stat.
# this represents the weapon's contribution. when equipment is built, this
# should be replaced by the equipped weapon's damage value. for now it stays
# at 20 so combat math is balanced for 3-swing kills on 60-80 hp enemies.
@export var base_melee_damage: int = 20

# tracks enemies already hit this swing — prevents multi-hit per swing
# but allows multiple different enemies to be hit (cleave behavior)
var _hit_this_swing: Array[Node] = []

# tracks if a slashwave has already been spawned this swing
var _wave_spawned_this_swing: bool = false

# cached sprite reference
@onready var sprite: AnimatedSprite2D = $animatedsprite2d

# directional hitboxes — populated in _ready by auto-detection.
# expects nodes named "hitboxleft", "hitboxright", "hitboxup", "hitboxdown".
var hitboxes: Dictionary = {
	"left":  null,
	"right": null,
	"up":    null,
	"down":  null,
}

# directional wave spawn markers — populated in _ready by auto-detection.
# expects Marker2D nodes named "wavespawnleft", "wavespawnright",
# "wavespawnup", "wavespawndown" placed where the slash should appear.
var wavespawns: Dictionary = {
	"left":  null,
	"right": null,
	"up":    null,
	"down":  null,
}

func _ready() -> void:
	super._ready()
	character_name = "warrior"
	speed = 200
	max_hp = 100
	hp = 100
	max_stamina = 25
	stamina = 25
	max_mana = 100
	mana = 100
	# attack is the SKILL stat (1 = beginner, 99 = mastered).
	# damage is computed via _calculate_melee_damage(), NOT this value directly.
	attack = 1
	defense = 1

	_detect_hitboxes()
	_detect_wavespawns()

	if sprite != null:
		if not sprite.frame_changed.is_connected(_on_frame_changed):
			sprite.frame_changed.connect(_on_frame_changed)

func _detect_hitboxes() -> void:
	# look up each directional hitbox and store it in the dictionary.
	# logs how many were found so missing nodes are easy to debug.
	var found := 0
	for dir in ["left", "right", "up", "down"]:
		var node_name: String = "hitbox" + dir
		if has_node(node_name):
			hitboxes[dir] = get_node(node_name)
			found += 1

func _detect_wavespawns() -> void:
	# detect the 4 wavespawn markers — one per direction.
	# missing markers are warned but not fatal: warrior still does melee damage,
	# the slash wave just won't fire in that direction.
	var found := 0
	for dir in ["left", "right", "up", "down"]:
		var node_name: String = "wavespawn" + dir
		if has_node(node_name):
			wavespawns[dir] = get_node(node_name)
			found += 1

# --- damage calculation ---

func _calculate_melee_damage() -> int:
	# total melee damage = base weapon damage + skill scaling bonus.
	# placeholder formula — tune as warrior progression is designed.
	# at attack=1 (default), total = 20 + 0 = 20.
	# at attack=50, total = 20 + (50-1)/2 = 44.
	# at attack=99, total = 20 + (99-1)/2 = 69.
	# this is the single source of truth for warrior melee damage; melee hits
	# and slashwave damage both derive from it so skill progression scales
	# both consistently.
	return base_melee_damage + int((attack - 1) / 2)

# --- attack flow ---

func attack_action() -> void:
	if is_attacking:
		return
	is_attacking = true
	# reset state for the new swing
	_hit_this_swing.clear()
	_wave_spawned_this_swing = false

	var anim := get_attack_animation(last_direction)
	if sprite != null and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		# explicitly reset frame to 0 — without this, the previous animation's
		# frame number can leak into the first frame_changed signal of the new
		# animation and trigger damage during the windup
		sprite.frame = 0

func _on_frame_changed() -> void:
	# during the damage window: scan hitbox for melee damage.
	# at the wave spawn frame: spawn the slash wave (once per swing).
	if not is_attacking:
		return
	if sprite == null:
		return
	if not sprite.animation.begins_with("attack"):
		return

	# melee damage: every frame in the contact window
	if sprite.frame >= contact_frame_start and sprite.frame <= contact_frame_end:
		_deal_melee_damage()

	# wave spawn: single specific frame, separate from melee window.
	# allows the wave to appear AFTER the visible swing extends instead of before.
	if sprite.frame == wave_spawn_frame and not _wave_spawned_this_swing:
		_spawn_slashwave()
		_wave_spawned_this_swing = true

func _deal_melee_damage() -> void:
	# pick which hitbox to scan based on the warrior's facing direction
	var box: Area2D = _get_active_hitbox()
	if box == null:
		return

	# scan all areas overlapping the active hitbox (enemy hurtboxes, etc.)
	for area in box.get_overlapping_areas():
		var parent := area.get_parent()
		_try_damage(parent)

	# also scan direct body overlaps in case enemies don't have hurtbox areas
	for body in box.get_overlapping_bodies():
		_try_damage(body)

func _spawn_slashwave() -> void:
	# spawn a slashwave projectile in the warrior's facing direction.
	# damage is calculated as a fraction of melee damage — so the wave scales
	# with skill progression alongside the melee swing.
	var dir: String = _last_direction_to_cardinal()
	var spawn_node: Marker2D = wavespawns.get(dir)
	if spawn_node == null:
		# no spawn marker for this direction — silently skip
		return

	var wave: SlashWave = SLASHWAVE_SCENE.instantiate()

	# add to a projectiles container if it exists, else current scene.
	# matches the same pattern enemies use for their projectiles.
	var projectiles_container: Node = get_tree().get_first_node_in_group("projectiles")
	if projectiles_container == null:
		projectiles_container = get_tree().current_scene
	projectiles_container.add_child(wave)

	# position at the spawn marker and set damage based on melee damage formula.
	# using _calculate_melee_damage() (not raw attack stat) ensures wave damage
	# scales with skill the same way melee does.
	wave.global_position = spawn_node.global_position
	wave.damage = int(_calculate_melee_damage() * wave_damage_ratio)

	# fire in the cardinal direction matching the swing
	wave.shoot(dir)

func _get_active_hitbox() -> Area2D:
	# returns the hitbox to use for the current attack direction.
	# uses snap-to-cardinal logic to match the animation system.
	var dir: String = _last_direction_to_cardinal()
	return hitboxes.get(dir)

func _last_direction_to_cardinal() -> String:
	# convert last_direction Vector2 into one of the 4 cardinals.
	# matches the snap-to-cardinal logic in get_attack_animation.
	if abs(last_direction.x) > abs(last_direction.y):
		return "right" if last_direction.x > 0 else "left"
	else:
		return "down" if last_direction.y > 0 else "up"

func _try_damage(target: Node) -> void:
	# damage a target if it's an enemy and hasn't been hit this swing.
	# uses _calculate_melee_damage() rather than the attack skill stat directly
	# so the damage formula is one place to tune.
	if target == null:
		return
	if target in _hit_this_swing:
		return
	if not target.is_in_group("enemies"):
		return
	if not target.has_method("take_damage"):
		return

	target.take_damage(_calculate_melee_damage())
	gain_attack_xp(5)
	_hit_this_swing.append(target)
