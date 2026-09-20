// stone_blend.gdshader — settles a saturated floor material into the grey
// around it, without dragging the grey along with it.
//
// WHY NOT modulate
// ----------------
// modulate multiplies the whole node by one colour, and that is the problem.
// The gold slab in underground.png is a muddy olive; knocking it back toward
// the room's grey by multiplying means lifting blue hard — Color(1.08, 1.22,
// 2.07) is what actually lands the gold on the right tone. But that same 2.07
// hits every other pixel on the layer, and the layer is not only gold:
//
//     gold fill        rgb(125, 102,  47)   saturation 0.63
//     purple floor     rgb( 58,  56,  67)   saturation 0.16
//     pit interior     rgb( 58,  56,  67)   saturation 0.16
//     dais edge fleck  same family as the floor
//
// Measured off the sheet, not guessed. Multiply the pit's 67 blue by 2.07 and
// it becomes 139: the hole at the centre of the arena and the speckled trim
// around the slab both turn bright blue, which is exactly what you see if you
// try it. A multiply cannot tell the gold from the grey because it never
// looks at either one.
//
// WHAT THIS DOES INSTEAD
// ----------------------
// Pulls every pixel toward its own luminance. How far a pixel actually moves
// is proportional to how saturated it already was, so the effect concentrates
// itself on exactly the pixels that need it:
//
//     blend 0.55   gold  0.63 sat -> 0.31 sat   rgb(125,102,47) -> (124,110,80)
//     blend 0.55   pit   0.16 sat -> 0.07 sat   rgb( 58, 56,67) -> ( 63, 61,63)
//
// The gold travels most of the way into the floor's family. The pit barely
// moves, because there was almost no saturation there to remove. One knob,
// and it self-limits on the pixels that should not change.
shader_type canvas_item;

// 0 leaves the art exactly as authored, 1 is fully grey. 0.55 puts the gold
// dais in the same family as the purple floor while keeping it readable as a
// different material — past about 0.80 it stops being a material at all and
// just looks like dirty floor.
uniform float blend : hint_range(0.0, 1.0) = 0.55;

// Multiplied on after the blend, to nudge the greyed result warm or cool so it
// sits in the room's palette instead of going flat neutral. Keep it near 1.0;
// this is a lean, not a recolour, and pushing it hard reintroduces the exact
// problem the blend just solved.
uniform vec4 stone_tint : source_color = vec4(1.0, 0.98, 0.94, 1.0);

// Desaturating toward mid-grey costs a little brightness on a dark sheet, so
// the slab reads dimmer than it did. This puts it back.
//
// MULTIPLIED, NOT ADDED, and that is the whole point. An additive lift of the
// same apparent strength would raise the pit's floor off black and wash the
// hole out into a grey smudge; a multiply leaves it proportionally as dark as
// it was — 58 becomes 63, not 84.
uniform float brightness : hint_range(0.5, 1.5) = 1.10;

// Rec. 709 luma rather than a flat channel average. It matters on this sheet:
// the gold carries most of its brightness in green, and averaging the channels
// would drop the slab visibly darker as it desaturates.
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);


void fragment() {
	vec4 src = texture(TEXTURE, UV);

	if (src.a < 0.004) {
		// Leave fully transparent pixels untouched. Tinting them costs nothing
		// visually but shows up the moment anything samples this layer.
		COLOR = src;
	} else {
		float l = dot(src.rgb, LUMA);
		vec3 settled = mix(src.rgb, vec3(l), blend) * stone_tint.rgb * brightness;
		COLOR = vec4(clamp(settled, 0.0, 1.0), src.a);
	}
}
