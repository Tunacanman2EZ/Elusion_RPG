// death_crumble.gdshader - the white shape a monster leaves as it breaks apart.
//
// Used only by deathburst.gd, on a copy of the monster's last frame that lives
// for half a second and is then freed. Never on a monster's own sprite: see
// baseenemy.gd's note on the hit flash for why a shader that stays attached to
// an enemy, carrying a state that can get stuck, was a mistake once already.
// This one has nothing to get stuck on - its node is gone in a moment.
//
// It draws every opaque pixel of the frame pure white (a silhouette - the
// flash), cut into BLOCK x BLOCK squares of the art's own pixels. As crumble
// goes from 0 to 1 the squares go out one by one, the top of the body before
// the bottom, in an order that looks random but is the same every time for
// the same pixels - so the shape breaks up rather than fading.
shader_type canvas_item;

// 0: the whole shape. 1: nothing left.
uniform float crumble : hint_range(0.0, 1.0) = 0.0;

// The size of a square, in the art's pixels.
uniform float block = 2.0;

// Where the frame is on its sheet, in the sheet's pixels (y and height), so
// "the top of the body" is the top of the frame and not of the whole sheet.
uniform float frame_top = 0.0;
uniform float frame_height = 1.0;

float scatter(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 square = floor(texel / block);
	float down = clamp((texel.y - frame_top) / max(frame_height, 1.0), 0.0, 1.0);
	// When this square goes: mostly chance, a third by height.
	float goes_at = 0.65 * scatter(square) + 0.35 * down;
	COLOR = vec4(1.0, 1.0, 1.0, a * step(crumble, goes_at));
}
