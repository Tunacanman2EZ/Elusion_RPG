# monstersync.gd - everyone in an area fights the same monsters.
#
# 6 Oct 2026, the owner: "shared monsters separate loot bags". Until 0.7.0 each
# game fought its own copy of every area's monsters, so two friends in the
# Field saw each other walk about (presence) but swung at different slimes.
#
# ONE GAME RUNS THEM. The presence server names a LEADER for each area - the
# game that has been in it longest - and that game's monsters are THE monsters:
# they think, chase, cast, respawn, exactly as a lone player's always have. It
# says what they are doing ten times a second. Every other game in the area is
# a FOLLOWER: its monsters are MIRRORS that stand where the leader says, play
# what the leader says and show the health the leader says (BaseEnemy, "SHARED
# MONSTERS"), and every hit its player or pet lands is sent to the leader,
# whose game applies it.
#
# WHY A GAME AND NOT THE SERVER. The server has no map, no collision and no AI,
# and growing them there is E3_SCOPE.md's option C, "a season". The leader is
# trusted with the monsters the way every game is already trusted with its own
# kills (E-3): no more, and no new door - a cheating leader can only do to the
# monsters what a cheating game could always do to its own.
#
# SEPARATE LOOT BAGS. When a monster dies, every game whose player hit it
# reports the kill itself (Combat.report_kill), so each helper gets their own
# XP and their own bag from the server's own roll; nobody's bag is anybody
# else's to see or take. The leader reports only if its own player helped.
#
# EACH GAME IS HURT ONLY BY WHAT IT DRAWS. A monster's shot, vine, spike or
# swing happens on the leader and is copied to every follower (the "ev" list),
# where it can only touch that follower's own player - so whether you were hit
# is decided on your screen, by what you could see and dodge, as it always was.
#
# HANDING OVER. When the leader leaves, the server names the next game in line,
# whose mirrors turn back into monsters where they stand - mid-fight, at the
# health they had - and it carries on, its respawner starting fresh clocks for
# the dead ones. When the link drops, a follower takes its monsters back and
# fights alone, as before 0.7.0. A game that has heard nothing about who leads
# runs its own monsters, so no presence server, an old one, or no other player
# all play exactly as they did.
#
# THE WIRE (inside presence's "w" world messages, leader to followers):
#   {"snap": [[id, x, y, anim, hp], ...]}       monsters that changed this tick
#   {"ev": [{"k": ..., ...}, ...]}              what happened, in order:
#       spawn {r: record}    a new monster       die {id, x, y}    it died
#       gone {id}            gone without dying  p   a shot        v  a vine
#       e     a boss spike   sp  a stalker pillar  m  a boss swing
#   {"wave": n}                                  the boss gauntlet's wave
#   {"full": true, "reset": bool, "part": i, "parts": n, "spawn": [records],
#    "wave": n}                                  everything, to a game joining
# A record is {id, o (the spot it was authored at, or ""), s (scene), pp (its
# parent), x, y, a, hp, mh, p (BaseEnemy.net_props())}.
# And presence's "h" (follower to leader): [[id, damage, element], ...].
extends Node

const NODE_NAME := "monstersync"
const Targets := preload("res://src/shared/targets.gd")
const StalkerScript := preload("res://src/enemies/bossstalker.gd")

enum Role { PENDING, LEAD, FOLLOW }

# How often the leader says what changed, and a follower sends its hits. The
# presence server relays at the same rate.
const TICK_SECONDS := 0.1
# How long a game that knows a presence server is there waits to hear who
# leads before running the monsters itself. Its monsters stand still meanwhile.
const PENDING_SECONDS := 2.0
# A follower that has heard nothing of the monsters this long asks again: the
# leader's answer to it walking in can race the scene it walked into.
const ASK_AGAIN_SECONDS := 1.5
# The smallest move worth sending: under a pixel is a monster standing still.
const MOVE_EPSILON := 0.5
# The presence server's own limits (presence.py MAX_HITS_PER_MESSAGE, MAX_HIT).
const MAX_HITS_PER_MESSAGE := 64
const MAX_HIT := 100000
# A full world is split so no message nears presence.py's MAX_WORLD_BYTES.
const RECORDS_PER_PART := 60
# What a leader's world may ask a follower to build - nothing outside these.
const ENEMY_SCENES := "res://scene/enemy/"
const PROJECTILE_SCENES := "res://scene/projectiles/"
# THE LEADER IS TRUSTED WITH WHERE MONSTERS ARE, NOT WITH HOW HARD THE FLOOR
# HITS YOU. Shots, swings and spikes are built here from this game's own copy
# of the monster, so their damage is this game's. Three numbers in a world
# message are not, and are held to what this game's own boss could do:
# a spike lands no sooner and reaches no further than any bossenemy.gd casts
# (every telegraph it authors is 0.46 s or more before its element scales it;
# every spike radius is SPIKE_BASE_RADIUS, 20, or less), and a stalker's pillar
# is held to the stalker's own (bossstalker.gd PILLAR_*) - see safe_spike()
# and safe_pillar_damage().
const MIN_SPIKE_TELEGRAPH := 0.4
const MAX_TELEGRAPH := 5.0
const MAX_SPIKE_RADIUS := 20.0
# The most monsters a follower will draw. Big Field, the busiest area, has 128;
# this is room for the gauntlet's adds on top, and a ceiling on a world message
# that tries to fill the screen.
const MAX_MONSTERS := 400

# -1 until the first decision, so that decision always runs _become().
var role: int = -1
var area_id: String = ""
# Where the presence link is: the Presence autoload in the game, a stand-in in
# the suite. Anything with its signals and shares()/my_id()/sharers()/
# leader_for()/send_world()/send_hits().
var link: Node = null
# Whose kill this is and where it is reported; a seam for the suite.
var report_kill: Callable = Callable(Combat, "report_kill")

var _enemies: Dictionary = {}      # net id -> enemy
var _next_id: int = 1
var _last_sent: Dictionary = {}    # net id -> the state last sent
var _events: Array = []            # (leader) waiting for the next tick
var _hits: Array = []              # (follower) waiting for the next tick
var _hit_ids: Dictionary = {}      # (follower) monsters this game's player hit
var _awaiting_full: bool = false   # (follower) nothing applies before everything
var _full_parts: Array = []        # (follower) a full world arriving in parts
var _pending_left: float = 0.0
var _tick_left: float = 0.0
var _ask_left: float = 0.0
var _sent_wave: int = -1
var _respawner_nodes: Array = []
var _containers: Dictionary = {}   # where this scene keeps its monsters


static func add_to(scene: Node) -> Node:
	var sync := (load("res://src/world/monstersync.gd") as GDScript).new() as Node
	sync.name = NODE_NAME
	scene.add_child(sync)
	return sync


func _init() -> void:
	add_to_group(&"monstersync")


func _ready() -> void:
	if link == null:
		link = get_node_or_null("/root/Presence")
	if area_id == "" and AreaRegistry != null:
		area_id = AreaRegistry.current_area_id()
	_tag_origins()
	var root: Node = get_tree().current_scene
	for e in _all_enemies():
		if root != null and e.get_parent() != null and root.is_ancestor_of(e):
			_containers[str(root.get_path_to(e.get_parent()))] = true
	if get_tree().current_scene != null:
		_respawner_nodes = _respawners(get_tree().current_scene)
	if link != null:
		link.lead_changed.connect(_on_lead)
		link.world_received.connect(_on_world)
		link.hits_received.connect(_on_hits)
		link.world_needed.connect(_on_need)
	if link == null or not link.shares():
		_become(Role.LEAD)
		return
	var known: int = link.leader_for(area_id)
	if known == -2:
		_become(Role.PENDING)
	else:
		_on_lead(area_id, known, link.sharers())


func has_authority() -> bool:
	"""True when this game runs the area's monsters: the leader, or alone."""
	return role == Role.LEAD


func is_following() -> bool:
	return role == Role.FOLLOW


func monsters() -> Dictionary:
	return _enemies


# =============================================================================
# WHO RUNS THEM
# =============================================================================

func _on_lead(area: String, leader_id: int, _sharers: int) -> void:
	if area != "" and area != area_id:
		return
	if leader_id < 0 or link == null or leader_id == link.my_id():
		if role != Role.LEAD:
			_become(Role.LEAD)
	elif role != Role.FOLLOW:
		_become(Role.FOLLOW)


func _become(new_role: int) -> void:
	var was: int = role
	role = new_role
	match new_role:
		Role.PENDING:
			# FROZEN UNTIL WE KNOW. Every monster is held still - as a mirror
			# with nothing to follow - so nothing fights in the moment before
			# the server says whose monsters these are.
			_pending_left = PENDING_SECONDS
			for e in _all_enemies():
				e.net_set_mirror(true)
		Role.LEAD:
			_hits.clear()
			_awaiting_full = false
			_full_parts.clear()
			# TAKEN OVER WHERE THEY STAND. A monster this game's player had
			# already hit as a follower is one it helped kill.
			for e in _all_enemies():
				if e.net_mirror:
					if e.net_id >= 0 and _hit_ids.has(e.net_id):
						e._net_local_hit = true
					e.net_set_mirror(false)
			_register_all(false)
			var top: int = 0
			for id in _enemies.keys():
				top = maxi(top, int(id))
			_next_id = maxi(_next_id, top + 1)
			_respawner_resume()
			_last_sent.clear()
			_events.clear()
			# FROM PENDING THE IDS ARE THIS GAME'S OWN, so anyone already
			# drawing monsters forgets theirs ("reset"); from FOLLOW they are
			# the old leader's, and carry on.
			if _sharing():
				_send_full(-1, was != Role.FOLLOW)
		Role.FOLLOW:
			_events.clear()
			for e in _all_enemies():
				e.net_set_mirror(true)
			_awaiting_full = true
			_full_parts.clear()
			_ask_left = ASK_AGAIN_SECONDS


func _sharing() -> bool:
	return link != null and link.shares() and link.sharers() > 0


func _respawner_resume() -> void:
	for node in _respawner_nodes:
		if is_instance_valid(node):
			node.resume_authority()


func _respawners(root: Node) -> Array:
	var found: Array = []
	for child in root.get_children():
		if child.has_method("resume_authority") and child.has_method("adopt"):
			found.append(child)
		found.append_array(_respawners(child))
	return found


# =============================================================================
# THE CLOCK
# =============================================================================

func _process(delta: float) -> void:
	match role:
		Role.PENDING:
			_pending_left -= delta
			if _pending_left <= 0.0:
				# Nobody said: run them. A late word from the server that
				# somebody else leads still turns this game into a follower.
				_become(Role.LEAD)
		Role.LEAD:
			_tick_left -= delta
			if _tick_left > 0.0:
				return
			_tick_left = TICK_SECONDS
			tick_lead()
		Role.FOLLOW:
			if _awaiting_full:
				_ask_left -= delta
				if _ask_left <= 0.0:
					_ask_left = ASK_AGAIN_SECONDS * 2.0
					if link != null and link.has_method("request_world"):
						link.request_world()
			_tick_left -= delta
			if _tick_left > 0.0:
				return
			_tick_left = TICK_SECONDS
			_flush_hits()


func tick_lead() -> void:
	"""(Leader.) Number anything new, and tell the others what changed."""
	_register_all(true)
	if _sharing():
		_send_delta()
	else:
		# NOBODY LISTENING: nothing to build up for later. A game that joins
		# is sent everything ("need"), not the backlog.
		_events.clear()


# =============================================================================
# THE LEADER
# =============================================================================

func _all_enemies() -> Array:
	var found: Array = []
	if not is_inside_tree():
		return found
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node) and node is BaseEnemy and not node.is_queued_for_deletion():
			found.append(node)
	return found


func _register_all(announce: bool) -> void:
	for e in _all_enemies():
		if e.net_id >= 0 and _enemies.get(e.net_id) == e:
			continue
		if e._death_resolved:
			continue
		var id: int = _next_id
		_next_id += 1
		_bind(e, id)
		if announce and _sharing():
			_events.append({"k": "spawn", "r": record_of(e)})
			_last_sent[id] = e.net_state()


func _bind(e: BaseEnemy, id: int) -> void:
	e.net_id = id
	e._net_sync = self
	_enemies[id] = e
	if not e.died.is_connected(_on_died):
		e.died.connect(_on_died.bind(e))
	if not e.tree_exiting.is_connected(_on_gone):
		e.tree_exiting.connect(_on_gone.bind(e))


func _on_died(e: BaseEnemy) -> void:
	if role != Role.LEAD or not is_instance_valid(e):
		return
	var id: int = e.net_id
	if _enemies.get(id) != e:
		return
	_enemies.erase(id)
	_last_sent.erase(id)
	if _sharing():
		_events.append({"k": "die", "id": id,
			"x": snappedf(e.global_position.x, 0.1), "y": snappedf(e.global_position.y, 0.1)})


func _on_gone(e: BaseEnemy) -> void:
	if not is_instance_valid(e):
		return
	var id: int = e.net_id
	if _enemies.get(id) != e:
		return
	_enemies.erase(id)
	_last_sent.erase(id)
	if role == Role.LEAD and _sharing() and is_inside_tree() and not is_queued_for_deletion():
		_events.append({"k": "gone", "id": id})


func record_of(e: BaseEnemy) -> Dictionary:
	"""Everything a follower needs to draw this monster from nothing."""
	var root: Node = get_tree().current_scene
	var parent: Node = e.get_parent()
	return {
		"id": e.net_id,
		"o": str(e.get_meta(&"net_origin", "")),
		"s": e.scene_file_path,
		"pp": str(root.get_path_to(parent)) if root != null and parent != null and root.is_ancestor_of(parent) else "",
		"x": snappedf(e.global_position.x, 0.1),
		"y": snappedf(e.global_position.y, 0.1),
		"a": e.current_anim,
		"hp": e.hp,
		"mh": e.max_hp,
		"p": e.net_props(),
	}


func _send_delta() -> void:
	var snap: Array = []
	for id in _enemies.keys():
		var e: BaseEnemy = _enemies[id]
		if not is_instance_valid(e) or e._death_resolved:
			continue
		var now: Array = e.net_state()
		var was: Variant = _last_sent.get(id)
		if was is Array and (was as Array).size() == 5 \
				and absf(float(now[1]) - float(was[1])) < MOVE_EPSILON \
				and absf(float(now[2]) - float(was[2])) < MOVE_EPSILON \
				and now[3] == was[3] and now[4] == was[4]:
			continue
		snap.append(now)
		_last_sent[id] = now
	var message: Dictionary = {}
	if not _events.is_empty():
		message["ev"] = _events
		_events = []
	if not snap.is_empty():
		message["snap"] = snap
	var wave: int = _wave()
	if wave != _sent_wave:
		message["wave"] = wave
		_sent_wave = wave
	if not message.is_empty():
		link.send_world(message)


func _send_full(to: int, reset: bool) -> void:
	var records: Array = []
	for id in _enemies.keys():
		var e: BaseEnemy = _enemies[id]
		if is_instance_valid(e) and not e._death_resolved:
			records.append(record_of(e))
			_last_sent[id] = e.net_state()
	var parts: int = maxi(1, ceili(float(records.size()) / float(RECORDS_PER_PART)))
	for part in range(parts):
		var chunk: Array = records.slice(part * RECORDS_PER_PART, (part + 1) * RECORDS_PER_PART)
		var message: Dictionary = {"full": true, "reset": reset, "part": part, "parts": parts,
			"spawn": chunk, "wave": _wave()}
		link.send_world(message, to)
	_sent_wave = _wave()


func _on_need(for_id: int) -> void:
	if role != Role.LEAD or link == null:
		return
	# WHAT CHANGED FIRST, THEN EVERYTHING. The newcomer ignores the delta (it
	# is waiting for the full world) and everyone else needs it, so after this
	# pair every game agrees on what was last sent.
	_register_all(true)
	_send_delta()
	_send_full(for_id, false)


func _on_hits(_from_id: int, hits: Array) -> void:
	if role != Role.LEAD:
		return
	for hit in hits:
		if not (hit is Array) or (hit as Array).size() != 3:
			continue
		var e: Variant = _enemies.get(int(hit[0]))
		if not is_instance_valid(e) or (e as BaseEnemy).net_mirror or (e as BaseEnemy)._death_resolved:
			continue
		(e as BaseEnemy).net_take_remote_hit(clampi(int(hit[1]), 1, MAX_HIT), clampi(int(hit[2]), 0, 64))


func leader_shot(enemy: BaseEnemy, projectile: Node, at: Vector2) -> void:
	"""(Leader, from BaseEnemy.spawn_projectile_node.) A shot, for every
	screen. Its aim is read off the projectile the caller already aimed."""
	if role != Role.LEAD or not _sharing() or enemy.net_id < 0:
		return
	var aim: Variant = projectile.get("velocity")
	if not (aim is Vector2) or (aim as Vector2) == Vector2.ZERO:
		aim = projectile.get("direction")
	var dir: Vector2 = (aim as Vector2).normalized() if aim is Vector2 else Vector2.DOWN
	_events.append({"k": "p", "id": enemy.net_id, "s": projectile.scene_file_path,
		"x": snappedf(at.x, 0.1), "y": snappedf(at.y, 0.1),
		"ax": snappedf(dir.x, 0.0001), "ay": snappedf(dir.y, 0.0001)})


func leader_event(enemy: Node, event: Dictionary) -> void:
	"""(Leader.) A vine, a spike, a pillar or a swing, for every screen."""
	if role != Role.LEAD or not _sharing():
		return
	var id: int = int(enemy.get("net_id")) if enemy != null else -1
	if id < 0:
		return
	event["id"] = id
	_events.append(event)


func _wave() -> int:
	var gauntlet: Node = get_tree().get_first_node_in_group(&"bossgauntlet") if is_inside_tree() else null
	return int(gauntlet.net_wave()) if gauntlet != null and gauntlet.has_method("net_wave") else -1


# =============================================================================
# THE FOLLOWER
# =============================================================================

func mirror_hit(enemy: BaseEnemy, amount: int, element: int) -> void:
	"""(From BaseEnemy.take_damage on a mirror.) Your hit, for the leader."""
	if role != Role.FOLLOW or enemy.net_id < 0:
		return
	_hit_ids[enemy.net_id] = true
	_hits.append([enemy.net_id, clampi(amount, 1, MAX_HIT), clampi(element, 0, 64)])


func _flush_hits() -> void:
	if _hits.is_empty() or link == null:
		return
	var batch: Array = _hits.slice(0, MAX_HITS_PER_MESSAGE)
	_hits = _hits.slice(MAX_HITS_PER_MESSAGE)
	link.send_hits(batch)


func _on_world(data: Dictionary) -> void:
	if role != Role.FOLLOW:
		return
	if bool(data.get("full", false)):
		_take_full_part(data)
		return
	if _awaiting_full:
		return
	apply_world(data)


func _take_full_part(data: Dictionary) -> void:
	var part: int = int(data.get("part", 0))
	if part == 0:
		_full_parts.clear()
	_full_parts.append(data)
	if part + 1 < int(data.get("parts", 1)):
		return
	var records: Array = []
	for piece in _full_parts:
		var spawn: Variant = piece.get("spawn", [])
		if spawn is Array:
			records.append_array(spawn)
	var first: Dictionary = _full_parts[0]
	_full_parts.clear()
	reconcile(records, bool(first.get("reset", false)), int(data.get("wave", -1)))


func reconcile(records: Array, reset: bool, wave: int) -> void:
	"""Make this game's monsters exactly the leader's: the same ones, where
	the leader has them. Each is matched first by its number, then by the spot
	it was authored at (so the gauntlet's bosses stay the ones behind its
	gates), and only then built; anything left over goes, silently."""
	if reset:
		for e in _all_enemies():
			e.net_id = -1
		_enemies.clear()
		_hit_ids.clear()
	var by_origin: Dictionary = {}
	for e in _all_enemies():
		if e.net_id >= 0 and _enemies.get(e.net_id) == e:
			continue
		var origin: String = str(e.get_meta(&"net_origin", ""))
		if origin == "":
			continue
		if not by_origin.has(origin):
			by_origin[origin] = []
		by_origin[origin].append(e)
	var kept: Dictionary = {}
	for r in records:
		if not (r is Dictionary):
			continue
		var e: BaseEnemy = _take_or_build(r, by_origin)
		if e == null:
			continue
		kept[e.get_instance_id()] = true
		_apply_record(e, r, true)
	for e in _all_enemies():
		if not kept.has(e.get_instance_id()) and not e._death_resolved:
			_enemies.erase(e.net_id)
			e.net_remove()
	_awaiting_full = false
	if wave > 0:
		var gauntlet: Node = get_tree().get_first_node_in_group(&"bossgauntlet")
		if gauntlet != null and gauntlet.has_method("net_jump_to"):
			gauntlet.net_jump_to(wave)


func _take_or_build(r: Dictionary, by_origin: Dictionary) -> BaseEnemy:
	var id: int = int(r.get("id", -1))
	if id < 0:
		return null
	var e: Variant = _enemies.get(id)
	if is_instance_valid(e) and not (e as BaseEnemy)._death_resolved:
		(e as BaseEnemy).net_set_mirror(true)
		return e
	var built: BaseEnemy = null
	var origin: String = str(r.get("o", ""))
	if origin != "" and by_origin.has(origin) and not (by_origin[origin] as Array).is_empty():
		built = (by_origin[origin] as Array).pop_front()
	if built == null:
		built = build_mirror(r)
	if built == null:
		return null
	_bind(built, id)
	built.net_set_mirror(true)
	return built


func build_mirror(r: Dictionary) -> BaseEnemy:
	"""A new mirror from a record: the same scene, set up as the leader's was
	before its _ready(), placed where the leader has it."""
	var path: String = str(r.get("s", ""))
	if not path.begins_with(ENEMY_SCENES) or not ResourceLoader.exists(path):
		return null
	if _enemies.size() >= MAX_MONSTERS:
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var node: Node = packed.instantiate()
	if not (node is BaseEnemy):
		node.free()
		return null
	var e: BaseEnemy = node
	var props: Variant = r.get("p", {})
	if props is Dictionary:
		e.net_apply_props(props)
	e.set_meta(&"net_origin", str(r.get("o", "")))
	_container(str(r.get("pp", ""))).add_child(e)
	e.net_set_mirror(true)
	var at := Vector2(float(r.get("x", 0.0)), float(r.get("y", 0.0)))
	e.global_position = at
	if props is Dictionary:
		e.spawn_position = Vector2(float(props.get("hx", at.x)), float(props.get("hy", at.y)))
	e.reset_physics_interpolation()
	for respawner in _respawner_nodes:
		if is_instance_valid(respawner):
			respawner.adopt(e)
	return e


func _container(path: String) -> Node:
	var root: Node = get_tree().current_scene
	# ONLY A PLACE THIS SCENE KEPT MONSTERS IN when it loaded. The path comes
	# from another game; it may name the y-sorted container the monsters live
	# in, and nothing else here.
	if root != null and _containers.has(path):
		var found: Node = root.get_node_or_null(NodePath(path))
		if found != null:
			return found
	for e in _all_enemies():
		if e.get_parent() != null:
			return e.get_parent()
	return root if root != null else self


func _apply_record(e: BaseEnemy, r: Dictionary, snap: bool) -> void:
	var max_now: int = int(r.get("mh", e.max_hp))
	if max_now > 0 and max_now != e.max_hp:
		e.max_hp = max_now
	e.net_apply_state(Vector2(float(r.get("x", e.global_position.x)), float(r.get("y", e.global_position.y))),
		str(r.get("a", "")), int(r.get("hp", e.hp)), snap)


func apply_world(data: Dictionary) -> void:
	"""(Follower.) One tick of the leader's world: what happened, then where
	everything is, then how far the gauntlet has got."""
	var events: Variant = data.get("ev", [])
	if events is Array:
		for event in events:
			if event is Dictionary:
				_apply_event(event)
	var snap: Variant = data.get("snap", [])
	if snap is Array:
		for state in snap:
			if not (state is Array) or (state as Array).size() != 5:
				continue
			var e: Variant = _enemies.get(int(state[0]))
			if is_instance_valid(e) and (e as BaseEnemy).net_mirror:
				(e as BaseEnemy).net_apply_state(Vector2(float(state[1]), float(state[2])),
					str(state[3]), int(state[4]))
	if data.has("wave") and int(data.get("wave", -1)) > 0:
		var gauntlet: Node = get_tree().get_first_node_in_group(&"bossgauntlet")
		if gauntlet != null and gauntlet.has_method("net_jump_to"):
			gauntlet.net_jump_to(int(data["wave"]))


func _apply_event(event: Dictionary) -> void:
	var kind: String = str(event.get("k", ""))
	var id: int = int(event.get("id", -1))
	var e: Variant = _enemies.get(id)
	var mirror: BaseEnemy = e if is_instance_valid(e) else null
	var at := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	match kind:
		"spawn":
			var r: Variant = event.get("r")
			if r is Dictionary:
				var made: BaseEnemy = _take_or_build(r, {})
				if made != null:
					_apply_record(made, r, true)
		"die":
			if mirror == null:
				return
			_enemies.erase(id)
			# YOUR KILL, IF YOU HELPED: reported from here, by this game, so
			# the server rolls this player's own bag.
			if _hit_ids.has(id):
				_hit_ids.erase(id)
				report_kill.call(mirror.get_enemy_id(), mirror.global_position,
					get_tree().get_first_node_in_group("player"))
			mirror.net_vanish()
		"gone":
			if mirror == null:
				return
			_enemies.erase(id)
			mirror.net_remove()
		"p":
			_replay_shot(mirror, event, at)
		"v":
			if mirror != null and mirror.has_method("_place_vine"):
				mirror.call("_place_vine", at, str(event.get("d", "down")))
		"e":
			var scene: PackedScene = _projectile_scene(str(event.get("s", "")))
			if mirror != null and scene != null and mirror.has_method("_spawn_one_eruption"):
				var spike: Vector2 = safe_spike(float(event.get("t", 0.9)), float(event.get("r", 20.0)))
				mirror.call("_spawn_one_eruption", _ground(), at, spike.x, spike.y, scene,
					int(event.get("sd", 0)))
		"sp":
			var pillar_scene: PackedScene = _projectile_scene(str(event.get("s", "")))
			if pillar_scene == null:
				return
			var pillar: Node2D = StalkerScript.make_pillar(pillar_scene,
				safe_pillar_damage(int(event.get("d", 0)), mirror),
				clampf(float(event.get("t", 0.0)), StalkerScript.PILLAR_TELEGRAPH, MAX_TELEGRAPH),
				int(event.get("el", -1)),
				clampf(float(event.get("r", 0.0)), 1.0, StalkerScript.PILLAR_RADIUS))
			if pillar != null:
				_ground().add_child(pillar)
				pillar.global_position = at
				pillar.reset_physics_interpolation()
		"m":
			if mirror != null and mirror.has_method("_land_swing"):
				mirror.call("_land_swing")


func _replay_shot(mirror: BaseEnemy, event: Dictionary, at: Vector2) -> void:
	var scene: PackedScene = _projectile_scene(str(event.get("s", "")))
	if scene == null:
		return
	var shot: Node = scene.instantiate()
	var aim := Vector2(float(event.get("ax", 0.0)), float(event.get("ay", 1.0)))
	if shot.has_method("shoot_vector"):
		shot.shoot_vector(aim)
	# THROUGH THE MIRROR'S OWN spawn_projectile_node() when it is still here:
	# the same tint, damage and element the leader's monster gave its shot.
	if mirror != null:
		mirror.spawn_projectile_node(shot, at)
		return
	var container: Node = get_tree().get_first_node_in_group("projectiles")
	if container == null:
		container = get_tree().current_scene
	container.add_child.call_deferred(shot)
	shot.set_deferred("global_position", at)
	shot.call_deferred("reset_physics_interpolation")


static func safe_spike(telegraph: float, radius: float) -> Vector2:
	"""(Follower.) A leader's boss spike held to what this game's own boss
	could cast: (telegraph, radius). See MIN_SPIKE_TELEGRAPH."""
	return Vector2(clampf(telegraph, MIN_SPIKE_TELEGRAPH, MAX_TELEGRAPH),
		clampf(radius, 1.0, MAX_SPIKE_RADIUS))


static func safe_pillar_damage(sent: int, boss: Node) -> int:
	"""(Follower.) A stalker pillar's damage, never more than this game's own
	copy of the boss gives its trail - BossEnemy.trail_damage(), or the
	stalker's own PILLAR_DAMAGE when that is 0 or the boss is already gone.
	An honest leader sends exactly that; nothing here can make it more."""
	var cap: int = StalkerScript.PILLAR_DAMAGE
	if boss != null and is_instance_valid(boss) and boss.has_method("trail_damage"):
		var own: int = int(boss.call("trail_damage"))
		if own > 0:
			cap = own
	return cap if sent <= 0 else mini(sent, cap)


func _projectile_scene(path: String) -> PackedScene:
	if not path.begins_with(PROJECTILE_SCENES) or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


func _ground() -> Node:
	var container: Node = get_tree().get_first_node_in_group("groundeffects")
	return container if container != null else get_tree().current_scene


# =============================================================================
# SETUP
# =============================================================================

func _tag_origins() -> void:
	# EVERY MONSTER THE SCENE WAS AUTHORED WITH is named by where it sits in
	# it - the same string on every machine that loads the same scene. That is
	# how a follower's placed boss is matched to the leader's, gate and all.
	# The respawner keys its census the same way and carries the key on to the
	# monsters it brings back.
	var root: Node = get_tree().current_scene
	if root == null:
		return
	for e in _all_enemies():
		if not e.has_meta(&"net_origin") and root.is_ancestor_of(e):
			e.set_meta(&"net_origin", str(root.get_path_to(e)))
