# startpanel.gd - THE MINIGAMES' START PANEL, ONE LOOK (0.161.0). The owner,
# of the Mage's Stand's lobby: "clean this up ... well upgrade", then "lets
# fix the other minigames with the same idea" - "we need healers run tanks
# and warriors and arena".
#
# The pieces every minigame's start panel is made of, so they all read alike:
# a thin gold rule between its parts, small gold section heads, HOW TO PLAY as
# a grid (a gold word, then its line), YOUR PARTY as seat cards (each READY,
# not ready, on the way, here or Open; her own warmer, with a thicker gold
# edge), what the party waits for in words, and the button - gold when it
# goes (Start, Start alone, Ready), plain when it takes Ready back.
#
# Static, no class_name (preloaded where used): it holds nothing.
extends RefCounted

const GOLD := Color(1.0, 0.86, 0.45)
const HINT := Color(0.82, 0.78, 0.7)
const READY_COLOUR := Color(0.55, 0.92, 0.5)
const OPEN_COLOUR := Color(0.55, 0.5, 0.45)
const CARD_BACK := Color(0.16, 0.13, 0.11)
const MINE_BACK := Color(0.26, 0.2, 0.1)
const SEAT_SIZE := Vector2(118.0, 50.0)
const GATE_SIZE := Vector2(62.0, 50.0)
const GO_BACK := Color(0.2, 0.15, 0.08)
const GO_HOVER := Color(0.27, 0.2, 0.1)
const BACK_BACK := Color(0.12, 0.1, 0.09)
const BACK_HOVER := Color(0.17, 0.14, 0.12)
const LOOKS := ["normal", "hover", "pressed"]


static func words(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func rule(colour: Color = GOLD) -> ColorRect:
	"""A thin line between the panel's parts."""
	var line := ColorRect.new()
	line.color = Color(colour, 0.25)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func head(text: String, colour: Color = GOLD) -> Label:
	"""A section's name, small, over it."""
	var label := words(text, 13, Color(colour, 0.7))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


static func how_grid(keys: Array, lines: Array, into: Array, key_colour: Color = GOLD,
		line_colour: Color = HINT, size: int = 15) -> GridContainer:
	"""HOW TO PLAY: a word in gold, then its line - the lines' labels go in
	`into`, so the screen can word them for a phone."""
	var grid := GridContainer.new()
	grid.name = "howto"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	for k in lines.size():
		var key := words(str(keys[k]) if k < keys.size() else "", size, key_colour)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(key)
		var line := words(str(lines[k]), size, line_colour)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(line)
		into.append(line)
	return grid


static func party_part(slots: Array, gate_colour: Color = Color(0, 0, 0, 0)) -> Dictionary:
	"""YOUR PARTY: a rule, its head and "N of M ready", a row of seats (each
	slot a seat's number, or -1 for the gate between them), what it waits for
	and a quieter line under it. {box, count, cards, line, side}."""
	var box := VBoxContainer.new()
	box.name = "party"
	box.add_theme_constant_override("separation", 8)
	box.visible = false
	box.add_child(rule())
	var head_row := HBoxContainer.new()
	box.add_child(head_row)
	head_row.add_child(head("YOUR PARTY"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(gap)
	var count := words("", 13, HINT)
	count.name = "count"
	head_row.add_child(count)
	var row := HBoxContainer.new()
	row.name = "seats"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var cards: Array = []
	for slot in slots:
		if int(slot) < 0:
			row.add_child(gate_slot(gate_colour))
		else:
			var card: PanelContainer = seat_card(int(slot))
			row.add_child(card)
			cards.append(card)
	var line := words("", 16, GOLD)
	line.name = "partyline"
	box.add_child(line)
	var side := words("", 13, HINT)
	side.name = "side"
	box.add_child(side)
	return {"box": box, "count": count, "cards": cards, "line": line, "side": side}


static func seat_card(seat: int) -> PanelContainer:
	"""A seat: a name, and ready or not."""
	var card := PanelContainer.new()
	card.name = "seat%d" % seat
	card.custom_minimum_size = SEAT_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BACK
	style.border_color = OPEN_COLOUR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var who := words("", 15, HINT)
	who.name = "who"
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.clip_text = true
	who.custom_minimum_size = Vector2(SEAT_SIZE.x - 10.0, 0)
	column.add_child(who)
	var said := words("", 12, HINT)
	said.name = "said"
	column.add_child(said)
	return card


static func gate_slot(colour: Color) -> PanelContainer:
	"""The gate between two sides of a wall (the Mage's Stand)."""
	var gate := PanelContainer.new()
	gate.name = "gate"
	gate.custom_minimum_size = GATE_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(colour.darkened(0.55), 0.9)
	style.border_color = colour.darkened(0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	gate.add_theme_stylebox_override("panel", style)
	var word := words("GATE", 12, colour.lightened(0.3))
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gate.add_child(word)
	return gate


static func seat_said(row: Dictionary, here: bool, ready_flag: int) -> Array:
	"""What a seat shows for its player's row ({name, flags, heard, me}; {} an
	open seat): [name, state, colour, border, hers, ready]."""
	if row.is_empty():
		return ["Open", "for the party", OPEN_COLOUR, Color(OPEN_COLOUR, 0.45), false, false]
	var mine: bool = bool(row.get("me", false))
	var name_text: String = str(row.get("name", "")) + (" (you)" if mine and str(row.get("name", "")) != "You" else "")
	var is_ready: bool = int(row.get("flags", 0)) & ready_flag != 0
	var state_text: String = "not ready"
	var colour: Color = HINT
	if not bool(row.get("heard", true)):
		state_text = "on the way..."
	elif not here:
		state_text = "here"
	elif is_ready:
		state_text = "READY"
		colour = READY_COLOUR
	return [name_text, state_text, colour, GOLD if mine else Color(colour, 0.7), mine,
		is_ready and here and bool(row.get("heard", true))]


static func paint_seats(cards: Array, said: Array) -> void:
	"""Each card as `said` has it (seat_said(), one a card)."""
	for k in mini(cards.size(), said.size()):
		var card: PanelContainer = cards[k]
		var one: Array = said[k]
		var who := card.find_child("who", true, false) as Label
		var state_line := card.find_child("said", true, false) as Label
		who.text = str(one[0])
		who.add_theme_color_override("font_color", GOLD if bool(one[4]) else (one[2] as Color).lightened(0.15))
		state_line.text = str(one[1])
		state_line.add_theme_color_override("font_color", one[2])
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = one[3]
		style.bg_color = MINE_BACK if bool(one[4]) else CARD_BACK
		style.set_border_width_all(3 if bool(one[4]) else 2)


static func ready_count(said: Array) -> int:
	var n: int = 0
	for one in said:
		if bool((one as Array)[5]):
			n += 1
	return n


static func waiting_text(rows: Array, said_ready: bool, ready_flag: int, counting: float) -> String:
	"""What the party waits for: the count, who is on their way, who has not
	pressed Ready."""
	if counting >= 0.0:
		return "Starting in %d..." % maxi(1, ceili(counting))
	if not said_ready:
		return "Press Ready when you are set."
	var coming: Array = []
	var waiting: Array = []
	for row in rows:
		if bool(row.get("me", false)):
			continue
		if not bool(row.get("heard", true)):
			coming.append(str(row.get("name", "")))
		elif int(row.get("flags", 0)) & ready_flag == 0:
			waiting.append(str(row.get("name", "")))
	if not coming.is_empty():
		return "Waiting for %s to arrive." % names_said(coming)
	if not waiting.is_empty():
		return "Waiting for %s to press Ready." % names_said(waiting)
	return "Everyone is ready."


static func names_said(names: Array) -> String:
	"""ann; ann and bob; ann, bob and cat."""
	if names.size() <= 1:
		return "".join(names)
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), str(names.back())]


static func go_button(text: String, pressed: Callable) -> Button:
	"""The panel's button: big, gold-edged."""
	var go := Button.new()
	go.name = "go"
	go.text = text
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(220, 42)
	go.add_theme_font_size_override("font_size", 18)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for look in LOOKS:
		var edge := StyleBoxFlat.new()
		edge.bg_color = GO_HOVER if look == "hover" else GO_BACK
		edge.border_color = GOLD
		edge.set_border_width_all(2)
		edge.set_corner_radius_all(4)
		edge.set_content_margin_all(6)
		go.add_theme_stylebox_override(look, edge)
	paint_go(go, true)
	if pressed.is_valid():
		go.pressed.connect(pressed)
	return go


static func paint_go(button: Button, go: bool) -> void:
	"""Gold for going (Start, Start alone, Ready); plain for taking it back."""
	var edge: Color = GOLD if go else Color(HINT, 0.35)
	for look in LOOKS:
		var style := button.get_theme_stylebox(look) as StyleBoxFlat
		if style != null and style.border_color != edge:
			style.border_color = edge
			style.bg_color = (GO_HOVER if look == "hover" else GO_BACK) if go else (BACK_HOVER if look == "hover" else BACK_BACK)
	button.add_theme_color_override("font_color", GOLD if go else HINT)
	button.add_theme_color_override("font_hover_color", GOLD.lightened(0.2) if go else HINT.lightened(0.2))
