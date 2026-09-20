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

var _waves: Dictionary = {}          # wave number -> Array[bossgate]
var _current: int = 0
var _live: Array = []                # bosses still standing in the current wave


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

	for gate in _waves.get(n, []):
		gate.open()
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
