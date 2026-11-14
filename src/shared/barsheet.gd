extends RefCounted
# barsheet.gd - every monster's health bar drawn together (0.155.0). The
# owner, of the limits sheet: "we need to optimize now", then "lets do it".
#
# Measured first (zz/drawparts.gd, xvfb + opengl3): 20 archers round you were
# 214 draw calls a frame and 121 with their bars hidden - a monster's bar and
# the number on it were 4.5 of its 5 draw calls. The renderer draws in one go
# what lies next to each other on one texture; a bar is two textures (its
# empty and its full), its number a third (the font's), and each monster's
# came between its sprite and the next monster's, so every bar broke the run
# three times. Lifting the bars onto a layer of their own alone saved 16 of
# 93: they still alternated empty, full, number, empty...
#
# So two things, together:
# - ONE SHEET. The four bar pictures (a monster's empty and full, a boss's
#   empty and full) are copied at run time into one texture, and each bar is
#   given cuts of it (AtlasTexture) in place of its own pictures. The art
#   files are untouched; the sheet exists only in memory.
# - ONE LAYER. A bar is drawn at BAR_Z, above the world, and its number one
#   above that (baseenemy.gd's readout, z 1 under the bar): every bar, then
#   every number. The cost of it: a bar shows over a wall or over a monster
#   standing in front, as a name does in most games.
#
# Where a picture cannot be read back the bar keeps its own pictures and is
# only lifted. (A headless run can read them: the suite checks the cuts
# against the pictures pixel for pixel.)

const BAR_Z := 20
const SOURCES := [
	"res://art/images/monsterhpempty.png",
	"res://art/images/monsterhpfull.png",
	"res://art/images/bosshpempty.png",
	"res://art/images/bosshpfull.png",
]
# A transparent pixel between pictures, so a cut never borrows its
# neighbour's edge.
const GAP := 1

static var _cuts: Dictionary = {}
static var _sheet: Texture2D = null
static var _built: bool = false


static func wear(bar: Node) -> void:
	"""Put `bar` on the sheet and the bars' layer. Safe to call twice."""
	var tbar := bar as TextureProgressBar
	if tbar == null:
		return
	tbar.texture_under = cut_of(tbar.texture_under)
	tbar.texture_progress = cut_of(tbar.texture_progress)
	tbar.texture_over = cut_of(tbar.texture_over)
	tbar.z_as_relative = false
	tbar.z_index = BAR_Z


static func cut_of(texture: Texture2D) -> Texture2D:
	"""The sheet's cut for one of SOURCES; anything else as it was."""
	if texture == null or texture is AtlasTexture:
		return texture
	if not _built:
		_build()
	var cut: Texture2D = _cuts.get(texture.resource_path) as Texture2D
	return cut if cut != null else texture


static func sheet() -> Texture2D:
	if not _built:
		_build()
	return _sheet


static func _build() -> void:
	_built = true
	var pictures: Array = []
	var width: int = 0
	var height: int = 0
	for path in SOURCES:
		var source: Texture2D = load(path) as Texture2D
		if source == null:
			continue
		var image: Image = source.get_image()
		if image == null or image.is_empty():
			continue
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		pictures.append([path, image])
		width = maxi(width, image.get_width())
		height += image.get_height() + GAP
	if pictures.is_empty():
		return
	var whole := Image.create(width, height, false, Image.FORMAT_RGBA8)
	whole.fill(Color(0, 0, 0, 0))
	var y: int = 0
	var regions: Dictionary = {}
	for pair in pictures:
		var image: Image = pair[1]
		whole.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, y))
		regions[pair[0]] = Rect2(0, y, image.get_width(), image.get_height())
		y += image.get_height() + GAP
	_sheet = ImageTexture.create_from_image(whole)
	for path in regions:
		var cut := AtlasTexture.new()
		cut.atlas = _sheet
		cut.region = regions[path]
		_cuts[path] = cut
