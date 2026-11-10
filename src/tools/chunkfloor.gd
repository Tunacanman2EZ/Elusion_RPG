# chunkfloor.gd - lays a scene's floor and water out for groundchunks.gd
# (0.137.3): each layer's cells set again chunk by chunk, and the chunks'
# ranges kept on it.
#
# WHEN. After painting the town's "ground" or "water" in the editor. Godot
# keeps a layer's cells in the order they were set, so new cells go on the
# end and the ranges no longer fit: the floor then loads whole, as it did
# before chunks (the log says "chunk ranges do not fit"), and the suite's
# _test_the_town_floor_in_chunks() fails. Nothing breaks; it is only slower.
#
# HOW. Open the scene (scene/elusion.tscn), open this file in the script
# editor, File > Run (Ctrl+Shift+X), then save the scene (Ctrl+S). A layer
# keeps the chunk size it had; a new one gets CHUNK_CELLS_SMALL. The same
# cells, the same picture - only their order and the ranges change.
#
# The Big Field is laid out by its builder (buildbigfield.gd), not this.
@tool
extends EditorScript

const GroundChunks := preload("res://src/world/groundchunks.gd")


func _run() -> void:
	var scene: Node = get_scene()
	if scene == null:
		print("chunkfloor: open the scene first (scene/elusion.tscn).")
		return
	var done: int = 0
	for layer_name in GroundChunks.LAYERS:
		var layer: TileMapLayer = scene.get_node_or_null(NodePath(layer_name)) as TileMapLayer
		if layer == null:
			continue
		var size: int = int(layer.get_meta(GroundChunks.SIZE_META, GroundChunks.CHUNK_CELLS_SMALL))
		GroundChunks.order_by_chunks(layer, size)
		var ranges: PackedInt32Array = layer.get_meta(GroundChunks.RANGES_META)
		print("chunkfloor: %s - %d cells in %d chunks of %d." % [layer_name, layer.get_used_cells().size(),
			int(ranges.size() / 4.0), size])
		done += 1
	if done == 0:
		print("chunkfloor: this scene has no \"ground\" or \"water\" layer at its root.")
		return
	EditorInterface.mark_scene_as_unsaved()
	print("chunkfloor: done - now save the scene.")
