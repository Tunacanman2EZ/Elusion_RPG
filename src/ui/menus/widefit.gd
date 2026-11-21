extends ColorRect
# A WIDE SCREEN FOR A MENU (0.168.12, the owner's 3440 x 1440 at 21:9). The
# game keeps its height, and a screen wider than 16:9 shows more of the
# world (settings.gd aspect_for()). A menu laid out on 1280 x 720 - the
# login, the character choice, game over - stretched its art to the width
# and cut off its top and bottom (the warrior's head on the login). Added to
# such a menu (`add_child(WideFit.new())`), this lays the menu out at
# 1280 x 720 in the middle of the screen, exactly as at 16:9, and is the dark
# backdrop that fills the sides. At 16:9, or narrower, nothing changes.

const VIEW := Vector2(1280.0, 720.0)
const BACKDROP := Color(0.02, 0.015, 0.035)


func _ready() -> void:
	name = "wideback"
	color = BACKDROP
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	get_parent().move_child(self, 0)
	get_viewport().size_changed.connect(_lay)
	_lay()


func _lay() -> void:
	var menu := get_parent() as Control
	if menu == null:
		return
	var extra: float = maxf(0.0, (get_viewport_rect().size.x - VIEW.x) * 0.5)
	var wide: bool = extra > 0.0
	menu.anchor_left = 0.5 if wide else 0.0
	menu.anchor_right = 0.5 if wide else 1.0
	menu.anchor_top = 0.0
	menu.anchor_bottom = 1.0
	menu.offset_left = -VIEW.x * 0.5 if wide else 0.0
	menu.offset_right = VIEW.x * 0.5 if wide else 0.0
	menu.offset_top = 0.0
	menu.offset_bottom = 0.0
	# this, the whole screen behind it
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -extra
	offset_right = extra
	offset_top = 0.0
	offset_bottom = 0.0
