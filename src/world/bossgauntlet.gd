# bossgauntlet.gd — the wave sequencer on the boss arena.
#
# ONE BOSS, THEN TWO, THEN THREE. Wave 1's gate is open when the player walks
# in; the rest stand behind ice. When every boss in the current wave is dead,
# the next wave's gates shatter.
#
# WHY THE GATES DECIDE THEIR OWN WAVE. Each bossgate carries `wave`, and this
# node only groups them. The alternative - a list of wave membership here -
# means the arena scene and this script both know the layout, and moving a
# boss in the editor silently disagrees with the sequence. One authored place.
#
# ONE GATE AT A TIME (0.143.0). The owner, of waves two and three: "should
# we release them 1 gate at a time then?" - and, asked how, "i need your best
# advice". A wave's gates open in RELEASE_ORDER (the arena easiest to read
# first, the one that takes the most floor last: Water then Wind; Ice, Earth,
# then Fire), the first at once and each next one when the boss let out last
# reaches its phase two (NEXT_AT_PHASE), after RELEASE_SECONDS of it
# fighting, or as soon as it falls. A gate due to open cracks and glows for
# WARN_SECONDS first (bossgate.gd warn(); WARN_ON_FALL when its partner has
# just fallen) and a banner names who is coming. The boss steps out
# (bossenemy.gd WALK_OUT_SECONDS) with its arena in phase one, so the worst of
# three arenas do not peak together. In a party the leader's game decides -
# a follower's bosses are its mirrors - and says how many are out ("rel",
# monstersync.gd); a follower opens what it is told.
#
# WHAT THIS DELIBERATELY DOES NOT DO: decide anything the server should own.
# A wave advances because a boss emitted `died` on this client, and a modified
# client can emit that without a fight - the same root as E-3. Until encounter
# state lives on the server this is a rule the game follows, not one it
# enforces, and it is worth being clear about which of those it is.
extends Node2D

# Emitted as each wave opens and when the last boss falls, so the HUD or an
# ambience track can react without polling.
signal wave_started(wave: int, bosses: int)
signal gauntlet_cleared()

# Beat between the last boss of a wave dying and the next gate shattering.
# Not zero: a wave that opens on the same frame as the kill reads as the game
# not noticing you won.
@export var wave_gap_seconds: float = 1.5

const RELEASE_ORDER := [Element.Type.LIGHT, Element.Type.WATER, Element.Type.WIND,
	Element.Type.ICE, Element.Type.EARTH, Element.Type.FIRE]
const NEXT_AT_PHASE := 1
const RELEASE_SECONDS := 30.0
const WARN_SECONDS := 3.0
const WARN_ON_FALL := 1.5
const BANNER_SECONDS := 2.6

var _waves: Dictionary = {}          # wave number -> Array[bossgate]
var _current: int = 0
var _live: Array = []                # bosses still standing in the current wave
# The current wave's gates in RELEASE_ORDER and the boss behind each (kept
# apart: an opened gate frees itself), how many are let out (warned or open),
# how long the last one let out has fought, and [gate, seconds] for each
# warned and not yet open.
var _order: Array = []
var _bosses: Array = []
var _released: int = 0
var _since_release: float = 0.0
var _opening: Array = []
var _banner: Label = null
var _banner_left: float = 0.0


# Joined in _init so the victory teleporter can find this sequencer by group
# without naming a path into the arena tree - and from _init so the membership
# exists the moment the node does, before any _ready runs. The signal below is
# the reactor's hook; this is how it locates the emitter.
func _init() -> void:
	add_to_group("bossgauntlet")


func _ready() -> void:
	# EVERY DESCENDANT, not just direct children. The gates sit under
	# ysortworld with the rest of the world so they sort against the bosses
	# they hold; requiring them to be children of this node would put them in
	# the wrong draw order to save one line here.
	for gate in _find_gates(self):
		var n: int = int(gate.wave)
		if not _waves.has(n):
			_waves[n] = []
		_waves[n].append(gate)

	if _waves.is_empty():
		push_warning("bossgauntlet: no bossgate nodes found - nothing to sequence")
		return

	if OS.is_debug_build():
		var tally := PackedStringArray()
		for n in _waves.keys():
			tally.append("wave %d: %d" % [int(n), _waves[n].size()])
		tally.sort()
		print("[GAUNTLET] %s" % ", ".join(tally))

	var first: int = _waves.keys().min()
	_start_wave(first)


func _find_gates(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child.get_script() != null and "wave" in child and child.has_method("open"):
			found.append(child)
		found.append_array(_find_gates(child))
	return found


func _start_wave(n: int) -> void:
	_current = n
	_live.clear()
	_order = ordered(_waves.get(n, []))
	_bosses = _order.map(_boss_of)
	_released = 0
	_since_release = 0.0
	_opening.clear()

	for gate in _order:
		var boss: Node = gate.get_node_or_null(gate.boss_path) if not gate.boss_path.is_empty() else null
		if boss == null:
			continue
		_live.append(boss)
		# ONE-SHOT, and bound to the boss so the handler knows which one fell
		# without searching. CONNECT_ONE_SHOT because BaseEnemy plays a death
		# animation before it frees itself, and a second emission during that
		# window would advance the wave twice.
		if not boss.died.is_connected(_on_boss_died):
			boss.died.connect(_on_boss_died.bind(boss), CONNECT_ONE_SHOT)

	wave_started.emit(n, _live.size())

	# A WAVE WITH NOTHING IN IT STILL ADVANCES. A gate authored with no boss
	# attached would otherwise stall the gauntlet forever with no error - the
	# room simply stops, which is the worst way for this to fail.
	if _live.is_empty():
		for gate in _order:
			gate.open()
		_advance()
		return
	# The first at once; the rest one at a time (ONE GATE AT A TIME).
	_release(n != _waves.keys().min(), 0.0)


# =============================================================================
# ONE GATE AT A TIME (0.143.0)
# =============================================================================

static func land_of(gate: Node) -> int:
	"""The land of the boss a gate holds (the gate's own tint if none)."""
	var path: NodePath = gate.get(&"boss_path") if gate.get(&"boss_path") is NodePath else NodePath()
	var boss: Node = gate.get_node_or_null(path) if not path.is_empty() else null
	if boss != null and boss.has_method(&"current_element"):
		return int(boss.call(&"current_element"))
	return int(gate.get(&"element"))


static func ordered(gates: Array) -> Array:
	"""`gates` in RELEASE_ORDER (a land not in it last, in the scene's order)."""
	var out: Array = gates.duplicate()
	out.sort_custom(func(a: Node, b: Node) -> bool: return _rank(a) < _rank(b))
	return out


static func _rank(gate: Node) -> int:
	var at: int = RELEASE_ORDER.find(land_of(gate))
	return at if at >= 0 else RELEASE_ORDER.size()


func _boss_of(gate: Variant) -> Node:
	if gate == null or not is_instance_valid(gate):
		return null
	var path: Variant = (gate as Node).get(&"boss_path")
	if not (path is NodePath) or (path as NodePath).is_empty():
		return null
	return (gate as Node).get_node_or_null(path)


func _release(say: bool, warn_seconds: float) -> void:
	"""Let the next gate of this wave out: warned for `warn_seconds` (none:
	open now), and a banner if `say`."""
	if _released >= _order.size():
		return
	var gate: Node = _order[_released]
	_released += 1
	if say:
		var land: String = Element.name_for(land_of(gate)).capitalize()
		_say(("%s joins the fight" % land) if _released > 1 else ("Wave %d: %s" % [_current, land]))
	if warn_seconds <= 0.0:
		_open_gate(gate)
		return
	if gate.has_method(&"warn"):
		gate.call(&"warn", warn_seconds)
	_opening.append([gate, warn_seconds])
	set_process(true)


func _open_gate(gate: Node) -> void:
	if is_instance_valid(gate):
		gate.open()
	_since_release = 0.0


func released() -> int:
	"""How many of this wave's gates are let out (warned or open)."""
	return _released


func waiting() -> int:
	"""How many of this wave's gates are still shut and not warned."""
	return _order.size() - _released


func _decides() -> bool:
	"""This game lets the next one out: nobody here is a mirror of the
	leader's (alone, or the leader)."""
	if _released >= _order.size():
		return false
	var boss: Variant = _bosses[_released] if _released < _bosses.size() else null
	return boss == null or not is_instance_valid(boss) or (boss as Node).get(&"net_mirror") != true


func _process(delta: float) -> void:
	var i: int = 0
	while i < _opening.size():
		_opening[i][1] = float(_opening[i][1]) - delta
		if float(_opening[i][1]) <= 0.0:
			_open_gate(_opening[i][0])
			_opening.remove_at(i)
			continue
		i += 1
	if _banner != null and _banner_left > 0.0:
		_banner_left -= delta
		_banner.modulate.a = clampf(minf(_banner_left / 0.5, (BANNER_SECONDS - _banner_left) / 0.3), 0.0, 1.0)
	if _released > 0 and _opening.is_empty() and _decides():
		var last: Variant = _bosses[_released - 1] if _released - 1 < _bosses.size() else null
		if last == null or not is_instance_valid(last) or (last as Node).get(&"_dying") == true \
				or (last as Node).get(&"_death_resolved") == true:
			_release(true, WARN_ON_FALL)
		else:
			if last.has_method(&"in_fight") and bool(last.call(&"in_fight")):
				_since_release += delta
			var phase: int = int(last.call(&"_current_phase")) if last.has_method(&"_current_phase") else 0
			if phase >= NEXT_AT_PHASE or _since_release >= RELEASE_SECONDS:
				_release(true, WARN_SECONDS)


func _say(text: String) -> void:
	if _banner == null:
		var layer := CanvasLayer.new()
		layer.name = "wavebanner"
		layer.layer = 40
		add_child(layer)
		_banner = Label.new()
		_banner.name = "banner"
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_banner.offset_top = 70.0
		_banner.offset_left = -300.0
		_banner.offset_right = 300.0
		_banner.add_theme_font_size_override("font_size", 22)
		_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_banner.add_theme_constant_override("outline_size", 6)
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.modulate.a = 0.0
		layer.add_child(_banner)
	_banner.text = text
	var gate: Variant = _order[_released - 1] if _released > 0 else null
	var land: int = land_of(gate) if gate != null and is_instance_valid(gate) else Element.Type.LIGHT
	_banner.add_theme_color_override("font_color", Color.WHITE.lerp(Element.colour_for(land), 0.5))
	_banner_left = BANNER_SECONDS
	set_process(true)


func banner_text() -> String:
	"""What the banner says now ("" while it shows nothing)."""
	return _banner.text if _banner != null and _banner_left > 0.0 else ""


func net_released() -> Array:
	"""(For monstersync.gd's "rel".) [wave, how many let out]."""
	return [_current, _released]


func net_release_to(wave: int, count: int, at_once: bool = false) -> void:
	"""(Follower.) The leader has let `count` of wave `wave` out: let the
	rest of them out here, warned as there (or `at_once`, catching up)."""
	if wave != _current:
		return
	while _released < mini(count, _order.size()):
		_release(not at_once, 0.0 if at_once else WARN_SECONDS)


# =============================================================================
# SHARED MONSTERS (0.7.0)
# =============================================================================
# Every game in a shared arena runs this sequencer, and each one advances it
# from its OWN bosses dying - a mirror's death is the leader's death, played
# here - so they agree without being told. The one thing a game cannot work
# out for itself is how far the fight had got before it walked in. That is
# what the leader's world says ("wave"), and net_jump_to() catches up to it.

func net_wave() -> int:
	return _current


func net_jump_to(n: int, rel: int = -1) -> void:
	"""Open every gate up to wave `n` at once and stand in it: the fight as it
	is on the game running it - of wave `n`, the first `rel` in RELEASE_ORDER
	(the leader's "rel"; -1, a leader from before 0.143.0, all of them).
	Bosses already dead there are expected to be gone or going
	(BaseEnemy._death_resolved) by the time this is called, so the wave's
	live list is only the ones still standing."""
	if n <= _current or not _waves.has(n):
		return
	for w in _waves.keys():
		if int(w) >= n:
			continue
		for gate in _waves[w]:
			if is_instance_valid(gate) and gate.has_method("open"):
				gate.open()
	_current = n
	_live.clear()
	_order = ordered(_waves.get(n, []))
	_bosses = _order.map(_boss_of)
	_opening.clear()
	_released = 0
	_since_release = 0.0
	for boss in _bosses:
		if boss == null or not is_instance_valid(boss) or bool(boss.get("_death_resolved")):
			continue
		_live.append(boss)
		if not boss.died.is_connected(_on_boss_died):
			boss.died.connect(_on_boss_died.bind(boss), CONNECT_ONE_SHOT)
	var out: int = _order.size() if rel < 0 else clampi(rel, 1, _order.size())
	while _released < out:
		_release(false, 0.0)
	wave_started.emit(n, _live.size())
	if _live.is_empty():
		_advance()


func _on_boss_died(boss: Node) -> void:
	_live.erase(boss)
	if _live.is_empty():
		_advance()


func _advance() -> void:
	var remaining: Array = []
	for n in _waves.keys():
		if int(n) > _current:
			remaining.append(int(n))

	if remaining.is_empty():
		gauntlet_cleared.emit()
		return

	var next: int = remaining.min()
	# Deferred through a timer rather than called straight from the died
	# signal: that signal fires inside the dying boss's own frame, and opening
	# a gate there means touching collision shapes mid-physics.
	var timer := get_tree().create_timer(wave_gap_seconds)
	timer.timeout.connect(func() -> void: _start_wave(next))
