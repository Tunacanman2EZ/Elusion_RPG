# marks.gd - the small marks the windows wear, drawn as pixels, not letters.
#
# The presence dot (filled online, hollow offline), the fold arrow (right when
# shut, down when open) and the guild ranks (a crown for the leader, a diamond
# for an officer).
#
# NOT GLYPHS, AND WHY. They were ●, ○, ▸, ▾, ♛ and ◆ - and none of those is in
# the game's font (Godot's built-in Open Sans). A desktop borrows a missing
# letter from a system font, so they looked right in the editor and the Windows
# build; a browser has no system fonts to borrow, and play.elusionrpg.com drew
# each one as a box with its code in it, in front of every name in the Staff,
# Friends, Guild and Trade windows. Drawn here they look the same everywhere,
# and the suite fails on any text the windows show that the font cannot draw
# (_test_every_ui_character_is_in_the_font).
#
# Preloaded where used (const Marks := preload(...)) rather than a class_name,
# as nametag.gd is, so a fresh checkout needs no editor rescan.
extends RefCounted

# Each mark as rows of pixels: # is the colour, anything else is clear.
const SHAPES := {
	"online": [
		"..###..",
		".#####.",
		"#######",
		"#######",
		"#######",
		".#####.",
		"..###..",
	],
	"offline": [
		"..###..",
		".#...#.",
		"#.....#",
		"#.....#",
		"#.....#",
		".#...#.",
		"..###..",
	],
	"closed": [
		"#...",
		"##..",
		"###.",
		"####",
		"###.",
		"##..",
		"#...",
	],
	"open": [
		"#######",
		".#####.",
		"..###..",
		"...#...",
	],
	"leader": [
		"#..#..#",
		"##.#.##",
		"#######",
		"#######",
		".#####.",
	],
	"officer": [
		"...#...",
		"..###..",
		".#####.",
		"#######",
		".#####.",
		"..###..",
		"...#...",
	],
}

# Built once per shape, colour and size: a list redraws every few seconds.
static var _cache: Dictionary = {}


static func texture(shape: String, colour: Color, scale: int = 1) -> Texture2D:
	"""The mark as a texture, each of its pixels `scale` screen pixels square.
	null for a shape this file does not have."""
	if not SHAPES.has(shape):
		return null
	var key: String = "%s|%s|%d" % [shape, colour.to_html(), scale]
	if _cache.has(key):
		return _cache[key]
	var rows: Array = SHAPES[shape]
	var width: int = str(rows[0]).length()
	var image := Image.create_empty(width * scale, rows.size() * scale, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = str(rows[y])
		for x in width:
			if row[x] == "#":
				image.fill_rect(Rect2i(x * scale, y * scale, scale, scale), colour)
	var made := ImageTexture.create_from_image(image)
	_cache[key] = made
	return made


static func make(shape: String, colour: Color, tip: String = "", width: int = 0) -> TextureRect:
	"""A TextureRect wearing the mark, centred in `width` (its own width when 0)
	and in the line's height, crisp at any size. Its "mark" meta is the shape,
	so what it shows can be asked without reading pixels."""
	var holder := TextureRect.new()
	holder.texture = texture(shape, colour)
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if width > 0:
		holder.custom_minimum_size = Vector2(width, 0)
	holder.tooltip_text = tip
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.set_meta("mark", shape)
	return holder
