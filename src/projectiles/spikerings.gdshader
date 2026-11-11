// spikerings.gdshader - every boss spike's warning ring in one draw
// (spikefx.gd, 0.137.5). Nothing here is art: a filled circle and an outline,
// as the spike used to draw itself with draw_circle() and draw_arc().
//
// ONE INSTANCE A WARNING SPIKE. Its transform is the spike's (where it
// stands, its size); the rest rides in its colour and custom data, written
// once, when the warning starts:
//
//   COLOR           the ring's colour (bossprojectile.gd ring_color, with its
//                   element's ring_alpha); the fill is it at 0.3 of its alpha
//   CUSTOM.x        when the warning started, on spikefx.gd's clock, mod WRAP
//   CUSTOM.y        how long it warns (telegraph_seconds)
//   CUSTOM.z        the ring's radius (ring_radius), in the spike's own units
//
// The mesh (spikefx.gd _ring_mesh()) is a fan for the fill (UV.x 0) and an
// outline (UV.x 1) of unit directions; UV.y is an outline vertex's distance
// from the radius, and its vertex alpha the soft edge. The fill grows from
// nothing to the ring over the warning, as it did - worked out here from
// `now`, so nothing is written while the spikes warn.
shader_type canvas_item;

// spikefx.gd's clock, mod WRAP (see there: "HALF FLOATS").
uniform float now_mod = 0.0;
const float WRAP = 16.0;

varying vec4 v_colour;

void vertex() {
	float age = mod(now_mod - INSTANCE_CUSTOM.x + WRAP, WRAP);
	float radius = INSTANCE_CUSTOM.z;
	v_colour = COLOR;
	if (UV.x < 0.5) {
		VERTEX *= radius * clamp(age / max(INSTANCE_CUSTOM.y, 0.001), 0.0, 1.0);
		v_colour.a *= 0.3;
	} else {
		VERTEX *= radius + UV.y;
	}
}

void fragment() {
	COLOR = v_colour;
}
