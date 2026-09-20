// element_recolour.gdshader — rotates a sprite's hue to an element's colour,
// leaving its shading intact.
//
// WHY A SHADER AND NOT modulate
// -----------------------------
// modulate MULTIPLIES. Multiplying can darken and it can filter, but it cannot
// move a hue: green art times blue is a darker green, every time. Measured
// against the real sheets, that limit lands exactly where it hurts —
//
//     electricsprite  0.27-0.32 saturation   modulate works
//     busharcher      0.17-0.31              modulate works
//     bushmage        0.35-0.43              marginal
//     firesprite      0.59-0.63              modulate FAILS
//     slime           0.58-0.69              modulate FAILS
//
// Three of five creature families cannot be recoloured by tinting at all, so a
// palette-swap variant of a slime was never going to be possible that way.
//
// This converts each pixel to HSV, REPLACES the hue, and converts back. Value
// and saturation survive untouched, which is what keeps the shading, the
// highlights and the outline reading as the same creature rather than a flat
// silhouette.
shader_type canvas_item;

// The element's hue, 0-1 (that is degrees/360). Element.hue_for() is the
// authored source; BaseEnemy sets it from enemy_data.element.
uniform float element_hue : hint_range(0.0, 1.0) = 0.0;

// 0 leaves the sprite exactly as drawn, 1 fully replaces the hue. Anything
// between blends, which is how a variant can read as "a bit off" rather than
// an entirely different creature.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

// Multiplies saturation after the shift. The default leaves it alone; above 1
// pushes a pale sheet toward a vivid element, below 1 drains a saturated one.
// The electric sprite at 0.28 wants roughly 1.6 to match the punch the slime
// gets for free at 0.66.
uniform float saturation_scale : hint_range(0.0, 3.0) = 1.0;

// PIXELS WITH ALMOST NO COLOUR ARE LEFT ALONE. Outlines, whites and near-greys
// carry no meaningful hue, so rotating them produces a coloured fringe on what
// should stay black. This is the threshold below which a pixel is considered
// achromatic and skipped.
uniform float grey_threshold : hint_range(0.0, 0.5) = 0.08;


vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}


vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


void fragment() {
	vec4 src = texture(TEXTURE, UV);

	// Fully transparent pixels are skipped before anything else — the maths
	// below is wasted on them and premultiplied edges can produce fringing.
	if (src.a < 0.004) {
		COLOR = src;
	} else {
		vec3 hsv = rgb_to_hsv(src.rgb);

		// Achromatic pixels keep their colour exactly. See grey_threshold.
		if (hsv.y < grey_threshold) {
			COLOR = src;
		} else {
			vec3 shifted = vec3(
				element_hue,
				clamp(hsv.y * saturation_scale, 0.0, 1.0),
				hsv.z
			);
			vec3 rgb = hsv_to_rgb(shifted);
			COLOR = vec4(mix(src.rgb, rgb, amount), src.a);
		}
	}
}
