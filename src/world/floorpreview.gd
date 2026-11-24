# floorpreview.gd - a floor kept once, drawn in the editor (0.176.2).
#
# The Big Field's ground holds no cells: buildbigfield.gd keeps them once, in
# its meta (groundchunks.gd, THE BIG FIELD'S FLOOR KEPT ONCE), and the game
# draws them in chunks. The editor would show the map with no floor at all,
# so in the editor alone this makes a picture of them: a layer of its own,
# an internal child (never saved, never in the scene's tree). In the game it
# does nothing.
#
# Painting on the ground in the editor still works - the cells go on the
# ground itself, and groundchunks.gd draws them with the rest.
@tool
extends TileMapLayer

# groundchunks.gd CELLS_META - written here, not preloaded: the editor runs
# only @tool scripts, and the suite holds the two the same.
const CELLS_META := &"chunk_cells"
const PICTURE := "editorfloor"


func _ready() -> void:
	if not Engine.is_editor_hint() or not has_meta(CELLS_META) or has_node(PICTURE):
		return
	var picture := TileMapLayer.new()
	picture.name = PICTURE
	picture.tile_set = tile_set
	picture.tile_map_data = get_meta(CELLS_META)
	add_child(picture, false, Node.INTERNAL_MODE_FRONT)
