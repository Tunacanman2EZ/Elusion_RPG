// fxparticles.gdshader - every effect's particle clouds in one draw a layer
// (fxparticles.gd, 0.174.4). Nothing is simulated on the processor: where a
// particle is at any moment is worked out here, from when its emitter began
// and its own number, the way CPUParticles2D rolled it.
//
// ONE INSTANCE AN EMITTER, ONE QUAD OF ITS MESH A PARTICLE (UV.x is the
// particle's number plus the corner's x, UV.y the corner's y). The
// instance's transform is the emitter's; the two numbers the transform does
// not use (its padding, MODEL_MATRIX[2].xy - the drawer stands at the origin)
// carry, at full precision, when it began emitting and when it stopped. The
// instance's colour: how fast the emitter is moving (rg, for particles left
// behind in the world), when its glide began, from when it began emitting
// (b), and its alpha (a). Its custom data: its seed, its row of numbers in
// `params`, its colour ramp's row and its scale curve's row in `ramps`.
//
// A GLIDE (fxemitter.gd glide(), the row's eighth texel: from, seconds,
// power): the emitter drawn going from `from` to where it stands, eased by
// progress to the power - a particle left in the world comes out where the
// glide was when it was born, a cloud carried along is where it is now.
shader_type canvas_item;

#include "res://src/shared/fxparticles.gdshaderinc"
