# talk.gd - characters talking in turn, from a script (0.171.0).
#
# The owner: "we need to make a story scene", then "i was thinking about
# adding the chat bubbles above characters", "there are 4 heros that means 4
# separate chats for each char", and "the chat bubbles start in town then
# work our way out". A scene is a text file a hero class -
# data/story/<scene>/<class>.txt, or all.txt for any hero without a file of
# its own - written like a script, a line a speaker:
#
#   shopkeeper: Are you lost?
#   hero: I was dead. I know I was.
#
# `hero` is whoever is playing. Blank lines and lines starting with # are
# notes. play() says each line in a speech bubble (speechbubble.gd) over its
# speaker, the next when the last has gone; Interact or Enter hurries a line
# (types it whole, then on to the next). A line whose speaker is not in the
# cast, or has gone, is skipped. After the last it says finished and goes.
#
# Where a bubble points: the speaker's talk_at() if it has one (the player's
# is over its name, the shopkeeper's over his head), else DEFAULT_AT. ONE
# STANDING UNDER ANOTHER speaks from below its feet (FEET_AT, the paper
# hanging down): a hero at the shop counter stands just under the
# shopkeeper, and a bubble over the hero's head covered him.
#
# MANY LINES, A PART EACH TIME (the owner: "we are going to add many lines
# for the story"). A script may be in parts, a line "---" between them: the
# first time the scene comes round it says the first part, the next time the
# second, and after the last nothing - until more are written. Counted a
# character, in the seen file beside the shopkeeper's greetings.
#
# ARRIVING SOMEWHERE (arrive()): the town (elusion.gd) and every area on
# field.gd ask for "arrive_<their scene's file name>" - arrive_elusion is the
# town, arrive_bigfield the Big Field through the portal. Said by the hero
# alone, ARRIVE_DELAY after arriving and after the area's story screen if
# one is up. AFTER A DEATH (yes, the owner - "when warrior dies he could
# arrive and say ..."): the game over screen notes who died (note_death()),
# and that hero's next arrival says the next part of AFTER_DEATH instead, or
# the arrival's own when that has none left. A new place to talk in is a new
# folder, no code. data/story/README.md lists them.
#
# ONE BUBBLE A SPEAKER: a line whose speaker is already saying something (the
# town's arrival lines while the shopkeeper's meeting begins) waits for it.
#
# Interact or Enter hurries a line but is NOT kept from the game: a player
# pressing Interact at the bank chest mid-speech opens the chest too.
#
# THE SCRIPTS ARE .txt, which an export leaves out unless it is told:
# export_presets.cfg's include_filter carries STORY_FILTER, and the suite
# holds both presets to it.
#
# No class_name: preload it by path.
extends Node

signal finished()

const Bubble := preload("res://src/shared/speechbubble.gd")
const STORY_DIR := "res://data/story/"
const STORY_FILTER := "data/story/*.txt"
# The file for any hero without one of its own.
const ANY_HERO := "all"
const DEFAULT_AT := Vector2(0, -30)
# A player's origin is 13 px over its feet; the tip just under them.
const FEET_AT := Vector2(0, 15)
# How near another speaker over this one must be for it to speak from below.
const UNDER_REACH := Vector2(90, 80)
# How long after arriving the hero speaks: past the fade in.
const ARRIVE_DELAY := 1.2
const ARRIVE_PREFIX := "arrive_"
const AFTER_DEATH := "after_death"
# The line between a script's parts.
const PART_BREAK := "---"

# [[speaker, words], ...], who is who, and the line being said.
var lines: Array = []
var cast: Dictionary = {}
var index: int = -1
var bubble: Node2D = null
# The line at `index` waits for its speaker's other bubble to go.
var held: bool = false
# An arrival waiting to be said (arrival()): its scene, how long until it
# may start, and the hero's class it was chosen for.
var waiting_scene: String = ""
var wait_left: float = 0.0
var hero_class: String = ""
var part: int = 0


static func script_path(scene: String, for_class: String) -> String:
	"""The scene's file for this hero, else its all.txt, else ""."""
	for who in [for_class, ANY_HERO]:
		if str(who) == "":
			continue
		var path: String = "%s%s/%s.txt" % [STORY_DIR, scene, str(who)]
		if FileAccess.file_exists(path):
			return path
	return ""


static func read_script(text: String) -> Array:
	"""[[speaker, words], ...] from a script's text: a line "who: words", the
	speaker in lower case; blank lines, # notes and lines with no speaker or
	no words are skipped. Only the first colon splits, so words may hold one."""
	var said: Array = []
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var colon: int = line.find(":")
		if colon <= 0:
			continue
		var who: String = line.substr(0, colon).strip_edges().to_lower()
		var words: String = line.substr(colon + 1).strip_edges()
		if who != "" and words != "":
			said.append([who, words])
	return said


static func read_parts(text: String) -> Array:
	"""A script's parts, each [[speaker, words], ...]: split at the lines that
	are PART_BREAK alone; a part with nothing said is dropped."""
	var parts: Array = []
	var current: PackedStringArray = PackedStringArray()
	for raw in (text + "\n" + PART_BREAK).split("\n"):
		if raw.strip_edges() == PART_BREAK:
			var said: Array = read_script("\n".join(current))
			if not said.is_empty():
				parts.append(said)
			current = PackedStringArray()
		else:
			current.append(raw)
	return parts


static func lines_for(scene: String, for_class: String, which: int = 0) -> Array:
	"""Part `which` of the scene's script for this hero; [] if there is none."""
	var path: String = script_path(scene, for_class)
	if path == "":
		return []
	var parts: Array = read_parts(FileAccess.get_file_as_string(path))
	return parts[which] if which >= 0 and which < parts.size() else []


static func play(parent: Node, said: Array, speakers: Dictionary) -> Node:
	"""Says `said` over `speakers` (name -> Node2D), as a child of `parent`;
	null when there is nothing to say."""
	if said.is_empty() or parent == null:
		return null
	var talk: Node = (load("res://src/shared/talk.gd") as GDScript).new()
	talk.name = "talk"
	talk.set("lines", said.duplicate(true))
	talk.set("cast", speakers.duplicate())
	parent.add_child(talk)
	return talk


static func seen_key(scene: String) -> String:
	"""This character's count of a scene, beside the shopkeeper's greetings
	in the seen file (speechbubble.gd times_said())."""
	var field: GDScript = load("res://src/world/field.gd") as GDScript
	return str(field.call("story_key")) + "#talk:" + scene


static func arrival_scene(area: Node) -> String:
	return ARRIVE_PREFIX + area.scene_file_path.get_file().get_basename()


static func arrive(area: Node, died: bool = false, for_class: String = "") -> Node:
	"""What the hero says arriving in `area`: after a death, the next part of
	AFTER_DEATH if any is left; else the next part of the area's own."""
	if died:
		var after: Node = arrival(area, for_class, AFTER_DEATH)
		if after != null:
			return after
	return arrival(area, for_class)


static func arrival(area: Node, for_class: String = "", scene: String = "") -> Node:
	"""The next part of a scene the hero says on arriving in `area` (its own
	arrive_ scene unless told); null when this hero has none left."""
	if scene == "":
		scene = arrival_scene(area)
	var hero: String = for_class if for_class != "" else str(CharacterData.active_class_id())
	var which: int = Bubble.times_said(seen_key(scene))
	if lines_for(scene, hero, which).is_empty():
		return null
	var talk: Node = (load("res://src/shared/talk.gd") as GDScript).new()
	talk.name = "arrivaltalk"
	talk.set("waiting_scene", scene)
	talk.set("wait_left", ARRIVE_DELAY)
	talk.set("hero_class", hero)
	talk.set("part", which)
	area.add_child(talk)
	return talk


static func note_death() -> void:
	GameState.back_from_death = seen_key("")


static func came_back_from_death() -> bool:
	"""True once, for the hero who died, on its next arrival; cleared either way."""
	var died: bool = GameState.back_from_death != "" and GameState.back_from_death == seen_key("")
	GameState.back_from_death = ""
	return died


static func at_for(speaker: Node2D) -> Vector2:
	if speaker.has_method("talk_at"):
		return speaker.call("talk_at")
	return DEFAULT_AT


func speaks_from_below(speaker: Node2D) -> bool:
	"""True when another of the cast stands just over this speaker, where a
	bubble over its head would cover them."""
	for other in cast.values():
		if other == speaker or not is_instance_valid(other) or not (other is Node2D) \
				or not (other as Node2D).is_inside_tree():
			continue
		var gap: Vector2 = (other as Node2D).global_position - speaker.global_position
		if gap.y < 0.0 and -gap.y <= UNDER_REACH.y and absf(gap.x) <= UNDER_REACH.x:
			return true
	return false


func _ready() -> void:
	if waiting_scene == "":
		_next()


func _process(delta: float) -> void:
	if waiting_scene != "":
		_wait_to_arrive(delta)
		return
	if held:
		_say_or_skip()
		return
	# A SPEAKER THAT WENT took its bubble with it, and a freed bubble never
	# says it is finished: go on without them.
	if index >= 0 and index < lines.size() and (bubble == null or not is_instance_valid(bubble)):
		_next()


func _wait_to_arrive(delta: float) -> void:
	wait_left -= delta
	if wait_left > 0.0 or _story_showing():
		return
	var hero: Node = get_tree().get_first_node_in_group("player")
	var scene: String = waiting_scene
	waiting_scene = ""
	if not (hero is Node2D):
		queue_free()
		return
	lines = lines_for(scene, hero_class, part)
	cast = {"hero": hero}
	Bubble.note_said(seen_key(scene))
	_next()


func _story_showing() -> bool:
	"""A story screen (storyscene.gd) up in this area: the hero waits for it."""
	var area: Node = get_parent()
	return area != null and area.get_children().any(func(child: Node) -> bool: return child is StoryScreen)


func _next() -> void:
	bubble = null
	index += 1
	_say_or_skip()


func _say_or_skip() -> void:
	held = false
	while index < lines.size():
		var speaker: Variant = cast.get(str(lines[index][0]))
		if is_instance_valid(speaker) and speaker is Node2D and (speaker as Node2D).is_inside_tree():
			if (speaker as Node2D).get_children().any(func(child: Node) -> bool: return child.get_script() == Bubble):
				held = true
				return
			var under: bool = speaks_from_below(speaker)
			bubble = Bubble.say(speaker, [str(lines[index][1])], FEET_AT if under else at_for(speaker), under)
			bubble.finished.connect(_next)
			return
		index += 1
	finished.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if bubble == null or not is_instance_valid(bubble):
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		bubble.call("hurry")
