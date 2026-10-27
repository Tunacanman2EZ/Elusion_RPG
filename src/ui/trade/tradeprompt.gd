# tradeprompt.gd - "Bram wants to trade", with See offer and No thanks (0.93.0).
#
# The owner, of trading: "starting a trade" was one of the four things wrong
# with it. Somebody opening a trade with you lit a dot on the Trade button and
# put a line on the status strip, and you had to find the window and open it to
# see what was offered, or to say no. Now a small card says who is asking,
# under the top of the screen, with two buttons:
#
#   See offer   opens the trade (the HUD's toggle_trade()), beside the bag
#   No thanks   POST /api/trade/cancel - the same request as the window's
#               Decline; the server tells the other side it was called off
#
# NOTHING NEW ON THE SERVER. The broadcast poll already carries the one-line
# `trade` summary the HUD reads (characterhud.gd, _read_trade()); this card is
# what it shows while the trade waits on your answer, and it goes when the
# trade does, when you accept, or when the window is open.
#
# Built by the HUD (attach()), no class_name, so a fresh checkout needs no
# editor rescan.
extends PanelContainer

const COLOUR := Color(0.62, 0.86, 1.0)
const FONT_SIZE := 14
# Below the status strip, which sits at the top of the screen.
const TOP := 44.0

# The suite's door into the request No thanks sends.
var cancel_request: Callable = Callable(Api, "post")

var hud: Node = null
var trade_id: String = ""
var words: Label = null
var see_button: Button = null
var no_button: Button = null
# A trade answered No here stays away even if a poll in flight still names it.
var _declined: String = ""


static func attach(on_hud: Node) -> Control:
	var card: Control = (load("res://src/ui/trade/tradeprompt.gd") as GDScript).new()
	card.name = "tradeprompt"
	card.set("hud", on_hud)
	on_hud.add_child(card)
	return card


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	words = Label.new()
	words.name = "words"
	words.add_theme_font_size_override("font_size", FONT_SIZE)
	words.add_theme_color_override("font_color", COLOUR)
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(words)
	see_button = _button("see", "See offer", _on_see)
	row.add_child(see_button)
	no_button = _button("no", "No thanks", _on_no)
	row.add_child(no_button)


func _button(id: String, text: String, then: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(88, 28)
	button.pressed.connect(then)
	return button


func _ready() -> void:
	# THE BAR'S LOOK: its theme and panel, as the touch menu takes them.
	var nav: Control = hud.get_node_or_null("%navframe") as Control if hud != null else null
	if nav != null:
		theme = nav.theme
		var style: StyleBox = nav.get_theme_stylebox("panel")
		if style != null:
			add_theme_stylebox_override("panel", style)


static func words_for(who: String) -> String:
	return "%s wants to trade with you." % who


func ask(id: String, who: String) -> void:
	"""Show the card for this trade; the same trade again changes nothing."""
	if id == "" or id == _declined:
		return
	trade_id = id
	words.text = words_for(who)
	no_button.disabled = false
	if not visible:
		visible = true
		move_to_front()
	_place()


func clear() -> void:
	trade_id = ""
	visible = false


func _place() -> void:
	if not is_inside_tree():
		return
	reset_size()
	var grow: float = 1.0
	if TouchControls.active:
		var menu: GDScript = load("res://src/ui/touchmenu.gd") as GDScript
		grow = clampf(float(menu.call("thumb_scale_of", self)), 1.0, 1.6)
	scale = Vector2(grow, grow)
	var screen: Vector2 = get_viewport_rect().size
	position = Vector2(maxf(0.0, (screen.x - size.x * grow) / 2.0), TOP).floor()


func _on_see() -> void:
	clear()
	if hud != null and hud.has_method("toggle_trade"):
		var panel: Control = hud.get("trade_panel") as Control
		if panel == null or not panel.visible:
			await hud.call("toggle_trade")


func _on_no() -> void:
	var asked: String = trade_id
	no_button.disabled = true
	var res: Dictionary = await cancel_request.call("/api/trade/cancel", {}, 6.0)
	if not is_instance_valid(self):
		return
	no_button.disabled = false
	if res.get("ok", false) or int(res.get("status", 0)) == 404:
		# 404: it had already gone - expired, or they called it off first.
		_declined = asked
		clear()
		if hud != null and hud.has_method("_mark_trade_button"):
			hud.call("_mark_trade_button", false)
		if hud != null and hud.has_method("set_world_status"):
			hud.call("set_world_status", "trade", "")
		return
	words.text = str(res.get("error", "Could not answer the trade."))
