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
# the arrival's own when that has none left. SIGNING IN (0.171.2, the owner:
# the line "upon entering town" was "suppose to play it in the first portal
# to town"): a sign-in says a hero's first part at most; every part after
# it waits for a trip into town - a portal, a ladder, leaving a minigame.
# A new place to talk in is a new folder, no code. data/story/README.md
# lists them.
#
# CHOICES (0.172.0, the owner: "a is a convo b is a convo and so is c thats
# what makes chat branching amazing", and a choice "that says trade"). In a
# script:
#
#   ? Lost? I was dead. = dead      a choice; = where it leads
#   ? Trade = @shop                 an @ is something done, not a branch
#   [dead]                          a branch starts
#   > food                          go on in another branch
#
# Lines running into a [branch] of their own end the conversation there.
# Choices in a row are offered together, under the hero (choicebox.gd); the
# pick is kept a character (CHOICE_SECTION), for scenes to come. ACTIONS:
# @shop opens the shop for a hero at its counter, @end just ends. Walking
# more than CHOICE_REACH from where they were asked ends it too. problems()
# says what in a script cannot be played; the suite holds every script to it.
# The Replay story button (the GM panel's Testing tab) is forget_story().
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
const ChoiceBox := preload("res://src/shared/choicebox.gd")
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
# What a choice may do instead of leading to a branch.
const ACTIONS := ["@shop", "@end"]
# Further than this from where they were asked, and the hero has walked off.
const CHOICE_REACH := 96.0
# Where the picks are kept, in the seen file.
const CHOICE_SECTION := "choices"

# [[speaker, words], ...], who is who, and the line being said.
var lines: Array = []
var cast: Dictionary = {}
var index: int = -1
var bubble: Node2D = null
# The line at `index` waits for its speaker's other bubble to go.
var held: bool = false
# The choices on offer, and where the hero stood when asked.
var choice_box: Node2D = null
var asked_at: Vector2 = Vector2.ZERO
# The scene these lines are from, for keeping a pick.
var scene_name: String = ""
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
	"""The steps of a script's text. [speaker, words] for "who: words" (the
	speaker in lower case; only the first colon splits, so words may hold
	one); ["?", [[words, where], ...]] for choices in a row; ["[", branch];
	[">", branch]. Blank lines, # notes and lines it cannot read are skipped
	(problems() names them)."""
	var said: Array = []
	for raw in text.split("\n"):
		var step: Array = read_line(raw.strip_edges())
		if step.is_empty():
			continue
		if str(step[0]) == "?" and not said.is_empty() and str(said[-1][0]) == "?":
			(said[-1][1] as Array).append_array(step[1])
		else:
			said.append(step)
	return said


static func read_line(line: String) -> Array:
	"""One line's step, or [] for a blank, a note or a line it cannot read."""
	if line == "" or line.begins_with("#"):
		return []
	if line.begins_with("?"):
		var split: int = line.rfind("=")
		if split < 0:
			return []
		var words: String = line.substr(1, split - 1).strip_edges()
		var where: String = line.substr(split + 1).strip_edges().to_lower()
		return [] if words == "" or where == "" else ["?", [[words, where]]]
	if line.begins_with("[") and line.ends_with("]"):
		var branch: String = line.substr(1, line.length() - 2).strip_edges().to_lower()
		return [] if branch == "" else ["[", branch]
	if line.begins_with(">"):
		var to: String = line.substr(1).strip_edges().to_lower()
		return [] if to == "" else [">", to]
	var colon: int = line.find(":")
	if colon <= 0:
		return []
	var who: String = line.substr(0, colon).strip_edges().to_lower()
	var said: String = line.substr(colon + 1).strip_edges()
	return [] if who == "" or said == "" else [who, said]


static func problems(text: String) -> Array:
	"""What in a script cannot be played: a line it cannot read, a choice or
	a > to a branch no [line] starts, an @ it does not know. [] if none."""
	var found: Array = []
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if line != "" and not line.begins_with("#") and line != PART_BREAK and read_line(line).is_empty():
			found.append("cannot read: " + line)
	for one_part in read_parts(text):
		var branches: Array = []
		for step in one_part:
			if str(step[0]) == "[":
				branches.append(str(step[1]))
		for step in one_part:
			var leads: Array = []
			if str(step[0]) == "?":
				for choice in step[1]:
					leads.append(str(choice[1]))
			elif str(step[0]) == ">":
				leads.append(str(step[1]))
			for where in leads:
				if where.begins_with("@"):
					if not ACTIONS.has(where):
						found.append("no such action: " + where)
				elif not branches.has(where):
					found.append("no [%s] for it to go to" % where)
	return found


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


static func play(parent: Node, said: Array, speakers: Dictionary, scene: String = "") -> Node:
	"""Says `said` over `speakers` (name -> Node2D), as a child of `parent`;
	null when there is nothing to say."""
	if said.is_empty() or parent == null:
		return null
	var talk: Node = (load("res://src/shared/talk.gd") as GDScript).new()
	talk.name = "talk"
	talk.set("lines", said.duplicate(true))
	talk.set("cast", speakers.duplicate())
	talk.set("scene_name", scene)
	parent.add_child(talk)
	return talk


static func seen_key(scene: String) -> String:
	"""This character's count of a scene, beside the shopkeeper's greetings
	in the seen file (speechbubble.gd times_said())."""
	var field: GDScript = load("res://src/world/field.gd") as GDScript
	return str(field.call("story_key")) + "#talk:" + scene


static func arrival_scene(area: Node) -> String:
	return ARRIVE_PREFIX + area.scene_file_path.get_file().get_basename()


static func arrive(area: Node, died: bool = false, for_class: String = "", signed_in: bool = false) -> Node:
	"""What the hero says arriving in `area`: after a death, the next part of
	AFTER_DEATH if any is left; else the next part of the area's own - only
	its first when they have just signed in."""
	if died:
		var after: Node = arrival(area, for_class, AFTER_DEATH)
		if after != null:
			return after
	return arrival(area, for_class, "", signed_in)


static func arrival(area: Node, for_class: String = "", scene: String = "", first_only: bool = false) -> Node:
	"""The next part of a scene the hero says on arriving in `area` (its own
	arrive_ scene unless told); null when this hero has none left, or when
	`first_only` and the first has been said."""
	if scene == "":
		scene = arrival_scene(area)
	var hero: String = for_class if for_class != "" else str(CharacterData.active_class_id())
	var which: int = Bubble.times_said(seen_key(scene))
	if (first_only and which > 0) or lines_for(scene, hero, which).is_empty():
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


static func just_signed_in() -> bool:
	"""True once after character select starts the town; cleared either way."""
	var signed: bool = GameState.just_signed_in
	GameState.just_signed_in = false
	return signed


static func visit(parent: Node, scene: String, for_class: String, speakers: Dictionary) -> Node:
	"""A scene said EVERY time, not once (a shop's menu, 0.172.0: "story once,
	menu every visit"): the next of its parts each visit, round again. Null
	when there is none for this hero."""
	var path: String = script_path(scene, for_class)
	if path == "":
		return null
	var parts: Array = read_parts(FileAccess.get_file_as_string(path))
	if parts.is_empty():
		return null
	var key: String = seen_key(scene)
	var which: int = Bubble.times_said(key) % parts.size()
	Bubble.note_said(key)
	return play(parent, parts[which], speakers, scene)


static func forget_story() -> int:
	"""The Replay story button: this character forgets every scene it has
	heard and every pick it made, so they play again from the start. How
	many it forgot."""
	var cfg := ConfigFile.new()
	if cfg.load(ControlsPanel.seen_path) != OK:
		return 0
	var mine: String = seen_key("").replace("/", "|")
	var forgot: int = 0
	for section in ["talk", CHOICE_SECTION]:
		if not cfg.has_section(section):
			continue
		for key in cfg.get_section_keys(section):
			if str(key).begins_with(mine):
				cfg.erase_section_key(section, key)
				forgot += 1
	cfg.save(ControlsPanel.seen_path)
	return forgot


static func note_choice(scene: String, where: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ControlsPanel.seen_path)
	cfg.set_value(CHOICE_SECTION, seen_key(scene).replace("/", "|"), where)
	cfg.save(ControlsPanel.seen_path)


static func choice_made(scene: String) -> String:
	"""Where this character's last pick in `scene` led, or ""."""
	var cfg := ConfigFile.new()
	if cfg.load(ControlsPanel.seen_path) != OK:
		return ""
	return str(cfg.get_value(CHOICE_SECTION, seen_key(scene).replace("/", "|"), ""))


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
	if choice_box != null:
		_watch_the_choice()
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
	scene_name = scene
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
	var jumps: int = 0
	while index < lines.size():
		var step: Array = lines[index]
		match str(step[0]):
			"[":
				# Ran into the next branch: this one is over.
				break
			">":
				index = branch_at(str(step[1]))
				jumps += 1
				if index < 0 or jumps > lines.size():
					break
				index += 1
				continue
			"?":
				_offer(step[1])
				return
		var speaker: Variant = cast.get(str(step[0]))
		if is_instance_valid(speaker) and speaker is Node2D and (speaker as Node2D).is_inside_tree():
			if (speaker as Node2D).get_children().any(func(child: Node) -> bool: return child.get_script() == Bubble):
				held = true
				return
			var under: bool = speaks_from_below(speaker)
			bubble = Bubble.say(speaker, [str(lines[index][1])], FEET_AT if under else at_for(speaker), under)
			bubble.finished.connect(_next)
			return
		index += 1
	_finish()


func _finish() -> void:
	if choice_box != null and is_instance_valid(choice_box):
		choice_box.queue_free()
	choice_box = null
	finished.emit()
	queue_free()


func branch_at(branch: String) -> int:
	"""Where [branch] starts in these lines, or -1."""
	return branch_where(lines, branch)


static func branch_where(steps: Array, branch: String) -> int:
	for i in steps.size():
		if str(steps[i][0]) == "[" and str(steps[i][1]) == branch:
			return i
	return -1


func _offer(choices: Array) -> void:
	"""The choices under the hero, once the hero's last bubble has gone."""
	var hero: Variant = cast.get("hero")
	if not (is_instance_valid(hero) and hero is Node2D and (hero as Node2D).is_inside_tree()):
		_finish()
		return
	if (hero as Node2D).get_children().any(func(child: Node) -> bool: return child.get_script() == Bubble):
		held = true
		return
	held = false
	var words: Array = []
	for choice in choices:
		words.append(str(choice[0]))
	asked_at = (hero as Node2D).global_position
	choice_box = ChoiceBox.offer(hero, words, FEET_AT)
	choice_box.picked.connect(_on_picked.bind(choices))


func _watch_the_choice() -> void:
	# Walked off, or the shop opened another way (Interact at the counter):
	# the answers go.
	var hero: Variant = cast.get("hero")
	if not is_instance_valid(choice_box) or not is_instance_valid(hero) \
			or (hero as Node2D).global_position.distance_to(asked_at) > CHOICE_REACH \
			or get_tree().get_first_node_in_group(&"openvendor") != null:
		_finish()


func _on_picked(choice: int, choices: Array) -> void:
	var where: String = str(choices[choice][1])
	if is_instance_valid(choice_box):
		choice_box.queue_free()
	choice_box = null
	if scene_name != "":
		note_choice(scene_name, where)
	if where.begins_with("@"):
		_act(where)
		_finish()
		return
	index = branch_at(where)
	if index < 0:
		_finish()
		return
	_next()


func _act(action: String) -> void:
	match action:
		"@shop":
			for vendor in get_tree().get_nodes_in_group(&"vendors"):
				if vendor.has_method("player_at_counter") and vendor.call("player_at_counter"):
					vendor.call("open_for_player")
					return


func _unhandled_input(event: InputEvent) -> void:
	if bubble == null or not is_instance_valid(bubble):
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		bubble.call("hurry")
