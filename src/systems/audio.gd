# audio.gd — autoload. The one place in the game that makes a noise.
#
# usage from anywhere:
#     Audio.play("attack_hit")              # heard the same wherever it happens
#     Audio.play_at("enemy_death", pos)     # quieter and panned when it's far away
#     Audio.play_music("music_menu")
#     Audio.set_bus_volume("SFX", 0.7)      # 0.0 - 1.0, for the Options sliders
#
# WORKS WITH NO SOUND FILES. Every id in SOUNDS below is currently an empty
# string, and an empty entry is a deliberate no-op — the call returns quietly
# instead of erroring. That is what lets the hooks go into the game NOW and the
# actual audio arrive later, one line at a time, without a flag day. Fill an
# entry in and that sound starts working everywhere it is already called from.
#
# WHY AN AUTOLOAD AND NOT AudioStreamPlayer NODES IN SCENES: a player parented
# to the thing making the sound dies with it. An enemy that plays its own death
# sound gets queue_free()d mid-playback and the sound is cut off — the one
# sound in the game guaranteed to be interrupted is the one marking a death.
# Pooled players living up here outlive whatever triggered them.
extends Node


# =============================================================================
# POOL SIZES
# =============================================================================

# How many sounds can overlap before the oldest gets cut off.
#
# This is the whole reason for pooling. A single shared AudioStreamPlayer
# restarts on every play() call, so three enemies dying in the same frame
# produce ONE death sound — which reads as a bug even though nothing errored.
# Twelve is comfortably more than this game stacks in practice.
const SFX_POOL_SIZE: int = 12
const SFX_2D_POOL_SIZE: int = 8

# Default random pitch spread, as a fraction either side of 1.0.
#
# Repeated identical samples are the classic tell of cheap game audio — twenty
# sword swings that are bit-for-bit the same stop sounding like swings and
# start sounding like a machine. A few percent of pitch wobble costs nothing
# and is the single highest-value trick in game SFX.
const DEFAULT_PITCH_VARIATION: float = 0.08

# Beyond this distance a positional sound is inaudible. Roughly two screens.
const SFX_2D_MAX_DISTANCE: float = 1200.0


# =============================================================================
# SOUND REGISTRY
# =============================================================================
# id -> res:// path. Callers use the id, never a path, so re-pointing a sound
# is one edit here rather than a search across fifty scripts.
#
# EVERY ENTRY IS EMPTY ON PURPOSE — see the header. Drop a file in and paste
# its path; that sound is then live at every call site already written.
#
# Suggested home: res://audio/sfx/<id>.ogg and res://audio/music/<id>.ogg
# (.ogg for anything longer than a second, .wav for short one-shots.)
const SOUNDS: Dictionary = {
	# --- combat ---
	"attack_swing":   "",  # any melee swing, all four classes
	"attack_hit":     "",  # weapon connects with an enemy
	"player_hurt":    "",  # the player takes damage
	"enemy_hurt":     "",  # an enemy takes damage
	"enemy_death":    "",  # an enemy dies
	"player_death":   "",  # the player dies

	# --- magic ---
	"spell_cast":     "",  # mage stalagmite, healer cast
	"projectile":     "",  # arrow / orb / poison ball leaving a muzzle
	"aura_on":        "",  # tank aura activating
	"refused":        "",  # a dull blip for "you can't do that"

	# --- items and loot ---
	"item_pickup":    "",  # picking anything up
	"coin":           "",  # gold specifically
	"potion":         "",  # drinking any consumable
	"bag_drop":       "",  # a loot bag hitting the ground
	"bag_open":       "",  # opening the loot panel
	"inventory_move": "",  # dropping an item into a slot

	# --- progression ---
	"level_up":       "",  # character level
	"skill_up":       "",  # attack / defence / agility / magic level
	"pet_summon":     "",  # a pet appearing

	# --- world and ui ---
	"ui_click":       "",  # any button
	"bank_open":      "",  # the chest opening
	"teleport":       "",  # stepping through a portal
	"door":           "",  # ladders, doors
	"lever":          "",  # a wall lever being thrown
	"spikes":         "",  # spike door rising or lowering

	# --- music (played through play_music, Music bus) ---
	"music_menu":     "",
	"music_town":     "",
	"music_field":    "",
	"music_crypt":    "",
}


# =============================================================================
# STATE
# =============================================================================

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_2d_pool: Array[AudioStreamPlayer2D] = []
var _music_player: AudioStreamPlayer = null

# next pool slot to steal when every player is busy. round-robin so a burst of
# sounds cannibalises the oldest rather than always killing the same one.
var _sfx_cursor: int = 0
var _sfx_2d_cursor: int = 0

# id -> loaded AudioStream. load() caches internally, but this avoids the
# lookup entirely on sounds that fire many times a second.
var _cache: Dictionary = {}

# ids already complained about, so a missing file warns ONCE rather than on
# every swing. An unfilled entry is silent by design; a filled entry pointing
# at a file that isn't there is a mistake worth hearing about.
var _warned: Dictionary = {}

# what play_music is currently playing, so asking for the same track twice
# doesn't restart it on every scene change.
var _current_music_id: String = ""


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# PROCESS_MODE_ALWAYS: audio must survive get_tree().paused. Without this
	# every sound cuts dead the instant a menu opens, including the click that
	# opened it.
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	for i in SFX_2D_POOL_SIZE:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = SFX_2D_MAX_DISTANCE
		add_child(p2)
		_sfx_2d_pool.append(p2)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	if OS.is_debug_build():
		var filled: int = 0
		for id in SOUNDS:
			if String(SOUNDS[id]) != "":
				filled += 1
		print("[BOOT] Audio: %d of %d sounds assigned" % [filled, SOUNDS.size()])


# =============================================================================
# PUBLIC — SOUND EFFECTS
# =============================================================================

func play(id: String, volume_db: float = 0.0, pitch_variation: float = DEFAULT_PITCH_VARIATION) -> void:
	# Non-positional: the same volume wherever it happened. Correct for UI,
	# pickups, level-ups and anything about the player themselves — those are
	# not events in the world, they are events that happened TO YOU.
	var stream: AudioStream = _stream_for(id)
	if stream == null:
		return

	var player: AudioStreamPlayer = _take_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _pitch(pitch_variation)
	player.play()


func play_at(id: String, world_position: Vector2, volume_db: float = 0.0, pitch_variation: float = DEFAULT_PITCH_VARIATION) -> void:
	# Positional: attenuates and pans with distance from the listener. Correct
	# for things happening out in the world — an enemy dying across the map
	# should not be as loud as one at your feet.
	#
	# NOTE this needs an AudioListener2D in the scene, or Godot falls back to
	# the active Camera2D — which every character scene already has, so it
	# works today with no extra setup.
	var stream: AudioStream = _stream_for(id)
	if stream == null:
		return

	var player: AudioStreamPlayer2D = _take_sfx_2d_player()
	player.stream = stream
	player.global_position = world_position
	player.volume_db = volume_db
	player.pitch_scale = _pitch(pitch_variation)
	player.play()


# =============================================================================
# PUBLIC — MUSIC
# =============================================================================

func play_music(id: String, restart_if_same: bool = false) -> void:
	# Asking for the track that is already playing is a no-op unless you force
	# it. Scene changes within one area would otherwise restart the music from
	# the top every time the player walks through a door.
	if id == _current_music_id and not restart_if_same and _music_player.playing:
		return

	var stream: AudioStream = _stream_for(id)
	if stream == null:
		# a missing track stops the old one rather than leaving the previous
		# area's music running under the new one.
		stop_music()
		return

	# loop the track if the import settings didn't already
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

	_current_music_id = id
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_current_music_id = ""
	if _music_player != null:
		_music_player.stop()


# =============================================================================
# PUBLIC — VOLUME  (for the Options screen)
# =============================================================================

func set_bus_volume(bus_name: String, linear: float) -> void:
	# Takes 0.0-1.0 because that is what a slider gives you. Godot wants
	# decibels, which are logarithmic — a slider wired straight to volume_db
	# does almost nothing across most of its travel and then drops off a cliff
	# at the end. linear_to_db() is the conversion that makes a slider feel
	# linear to a human ear.
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("Audio: no bus named '%s' — check default_bus_layout.tres" % bus_name)
		return

	linear = clampf(linear, 0.0, 1.0)
	# exactly zero is -inf dB; mute the bus instead so it's unambiguous
	AudioServer.set_bus_mute(idx, is_zero_approx(linear))
	if linear > 0.0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func get_bus_volume(bus_name: String) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


# =============================================================================
# INTERNAL
# =============================================================================

func _stream_for(id: String) -> AudioStream:
	# Resolves an id to a stream, or null for "deliberately silent".
	if not SOUNDS.has(id):
		# an id that isn't in the registry IS a typo — warn once.
		if not _warned.has(id):
			_warned[id] = true
			push_warning("Audio: no sound registered under id '%s'" % id)
		return null

	var path: String = String(SOUNDS[id])
	if path == "":
		return null  # not assigned yet: silent on purpose, not an error

	if _cache.has(id):
		return _cache[id]

	if not ResourceLoader.exists(path):
		if not _warned.has(id):
			_warned[id] = true
			push_warning("Audio: '%s' points at a missing file: %s" % [id, path])
		return null

	var stream: AudioStream = load(path)
	_cache[id] = stream
	return stream


func _take_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	# everything busy — steal the next one in rotation
	var p_steal: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_pool.size()
	return p_steal


func _take_sfx_2d_player() -> AudioStreamPlayer2D:
	for p in _sfx_2d_pool:
		if not p.playing:
			return p
	var p_steal: AudioStreamPlayer2D = _sfx_2d_pool[_sfx_2d_cursor]
	_sfx_2d_cursor = (_sfx_2d_cursor + 1) % _sfx_2d_pool.size()
	return p_steal


func _pitch(variation: float) -> float:
	if variation <= 0.0:
		return 1.0
	return randf_range(1.0 - variation, 1.0 + variation)
