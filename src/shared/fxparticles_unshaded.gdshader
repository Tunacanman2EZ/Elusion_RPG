// fxparticles_unshaded.gdshader - fxparticles.gdshader for clouds drawn
// unshaded (a CanvasItemMaterial's LIGHT_MODE_UNSHADED, the frost's glints):
// the same shader, untouched by the area's lights.
shader_type canvas_item;
render_mode unshaded;

#include "res://src/shared/fxparticles.gdshaderinc"
