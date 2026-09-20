// bossgate.gdshader — the ice prism a boss waits inside.
//
// A BOX, NOT A PANE. The first version drew a flat wall in front of the boss,
// which reads as a barrier you walk up to rather than a container something is
// held in. This draws a square prism seen slightly from above: a top face, a
// front face, and lit edges where they meet. The boss stands inside it.
//
// DRAWN TWICE PER PRISM, once behind the boss and once in front - see
// bossgate.tscn. `back_face` picks which half. The near half is thinner so the thing
// inside stays readable; the far half is heavier so the box has a back to it.
// Two draws is what gives "inside" instead of "behind glass".
//
// PROCEDURAL, so it needs no art and scales to any prism size. TINTED from
// Element.COLOURS[element] by bossgate.gd - the same palette the recolour
// shader puts on the boss itself, so the ice and its occupant always agree.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.40, 0.91, 0.98, 1.0);

// Face fill. Low: the point of a transparent prism is seeing what is in it.
uniform float alpha : hint_range(0.0, 1.0) = 0.30;

// Edges carry the shape. They are opaque enough to read at a glance against
// a dark crypt floor, which the faces are not.
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.85;

// How tall the top face is, and how far it insets - together these are the
// camera angle. Matching the game's own tile perspective matters more than
// either value alone.
uniform float top_height : hint_range(0.0, 0.5) = 0.20;
uniform float top_inset : hint_range(0.0, 0.5) = 0.14;

uniform float shards : hint_range(1.0, 24.0) = 6.0;
uniform float shimmer_speed : hint_range(0.0, 3.0) = 0.30;

// 0 = sealed, 1 = gone. Driven by bossgate.gd so the prism shatters column by
// column rather than dimming.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

// true for the half drawn BEHIND the boss.
// NAMED back_face, NOT `far`. `near` and `far` are reserved in older GLSL
// dialects, and a uniform that trips the parser fails the whole shader -
// which would not have surfaced here, because the first two builds never
// issued a draw call for the shader to fail on.
uniform bool back_face = false;

float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453123); }

// Signed distance to a line through a,b - used for the sloped top edges.
float line_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 uv = UV;
	float px = fwidth(uv.x) * 1.6;          // edge width in UV, resolution-independent

	// THE TOP FACE is a trapezoid: narrow at the very top, full width where it
	// meets the front face. That single shape is what makes a flat rectangle
	// read as a box with a lid.
	float t = clamp(uv.y / max(top_height, 0.0001), 0.0, 1.0);
	float half_w = mix(0.5 - top_inset, 0.5, t);
	bool on_top = uv.y < top_height && abs(uv.x - 0.5) < half_w;
	bool on_front = uv.y >= top_height;

	// Edges: the prism's silhouette plus the seam where the lid meets the wall.
	vec2 tl = vec2(0.5 - (0.5 - top_inset), 0.0);
	vec2 tr = vec2(0.5 + (0.5 - top_inset), 0.0);
	float e = 1.0;
	e = min(e, line_dist(uv, tl, vec2(0.0, top_height)));   // left slope
	e = min(e, line_dist(uv, tr, vec2(1.0, top_height)));   // right slope
	e = min(e, abs(uv.y - top_height));                     // the seam
	e = min(e, abs(uv.y - 1.0));                            // base
	e = min(e, line_dist(uv, tl, tr));                      // lid's far edge
	e = min(e, on_front ? abs(uv.x) : 1.0);                 // front left
	e = min(e, on_front ? abs(uv.x - 1.0) : 1.0);           // front right
	float edge = 1.0 - smoothstep(0.0, px * 2.0, e);

	// Vertical shards across the front face, so the ice has grain.
	//
	// THE FAR HALF IS OFFSET HALF A SHARD. Drawn at the same columns as the
	// near half, the two facet patterns land on top of each other and stack
	// into hard bright/dark striping - which reads as gaps in the glass
	// rather than as grain in it. Half a column apart, they interleave.
	float shard_shift = back_face ? 0.5 : 0.0;
	float column = floor(uv.x * shards + shard_shift);
	float phase = hash11(column) * 6.2831853;
	float across = abs(fract(uv.x * shards + shard_shift) - 0.5) * 2.0;
	float facet = on_front ? smoothstep(0.70, 1.0, across) : 0.0;
	float shimmer = 0.5 + 0.5 * sin(uv.y * 5.0 + TIME * shimmer_speed + phase);

	// SHATTERS COLUMN BY COLUMN. Each shard leaves on its own offset so the
	// prism breaks apart instead of fading out.
	float leave = hash11(column + 13.0) * 0.55;
	float alive = 1.0 - smoothstep(leave, leave + 0.4, dissolve);

	// Grain modulates the FILL a little instead of only the colour, so the
	// glass has depth without the hard banding.
	float face_a = alpha * (on_top ? 1.30 : 1.0) * (back_face ? 1.15 : 0.62)
		* (0.88 + facet * 0.24);
	vec3 colour = tint.rgb
		+ (on_top ? 0.30 : 0.0)      // the lid catches the light
		+ facet * 0.20
		+ shimmer * 0.07;

	float a = face_a;
	if (!on_top && !on_front) { a = 0.0; }   // outside the trapezoid's shoulders
	a = max(a, edge * edge_alpha);
	a *= alive;

	COLOR = vec4(colour, clamp(a, 0.0, 1.0));
}
