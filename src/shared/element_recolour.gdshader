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

// THE OUTFIT MASK. Negative (the default) recolours every coloured pixel, as it
// always did. Set to the outfit's own hue (0-1, e.g. the bush mage's green robe
// at ~0.29) and only pixels whose ORIGINAL hue is within source_hue_band of it
// get recoloured - so a robe changes element while skin, gold and other accents
// keep the colour they were drawn in. BaseEnemy feeds these from EnemyData.
uniform float source_hue : hint_range(-1.0, 1.0) = -1.0;
uniform float source_hue_band : hint_range(0.0, 0.5) = 0.5;

// TINT THE GREYS TOWARD THE ELEMENT. Hue rotation can only move a pixel that
// already has a hue, so a mostly-grey creature - the boss is ~half grey/black -
// barely changes between elements: same dark body, only the crown and effects
// differ. Above 0, achromatic pixels are pushed toward element_hue at this
// saturation, keeping their brightness, so the whole silhouette reads as its
// element (a fire boss goes dark-warm, an ice boss dark-cool). 0 leaves greys
// exactly as drawn (the default, right for creatures that are already colourful).
// Pure black stays black - a tint at zero brightness is still black - so outlines
// survive.
uniform float grey_tint : hint_range(0.0, 1.0) = 0.0;


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

		// OUTSIDE THE OUTFIT? Keep it. When source_hue is set (>= 0), a pixel
		// whose original hue is farther than source_hue_band from it is not part
		// of the garment being recoloured - it is skin, gold, an accent - so it
		// is left exactly as drawn. Distance is measured the short way around the
		// hue wheel so red at 0.98 and red at 0.02 count as near, not opposite.
		float hue_dist = abs(hsv.x - source_hue);
		hue_dist = min(hue_dist, 1.0 - hue_dist);
		bool outside_outfit = (source_hue >= 0.0) && (hue_dist > source_hue_band);

		if (outside_outfit) {
			// An accent outside the outfit band — skin, gold, a jewel. Never
			// touched, not even tinted; the whole point is to leave it be.
			COLOR = src;
		} else if (hsv.y < grey_threshold) {
			// Achromatic: outline, grey, near-black. Left alone by default, but
			// pushed toward the element when grey_tint is on, so a grey-bodied
			// creature still changes with its element instead of staying identical.
			if (grey_tint > 0.0) {
				vec3 tinted = hsv_to_rgb(vec3(element_hue, grey_tint, hsv.z));
				COLOR = vec4(mix(src.rgb, tinted, amount), src.a);
			} else {
				COLOR = src;
			}
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
