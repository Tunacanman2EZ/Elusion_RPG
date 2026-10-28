// swarm.gdshader - every swarmling of the endless run, drawn in one batch
// (swarm.gd). The art is the small slime's own sheet (art/enemy/slime.png,
// 48 px cells); nothing is drawn here that is not on it.
//
// ONE MULTIMESH, NO NODES. Each instance is a swarmling: its transform holds
// where it stands now, and the rest of what it needs rides in its colour and
// custom data, written by swarm.gd at its own step (20 a second):
//
//   CUSTOM.xy  where it stood one step ago, less where it stands now - the
//              walk is drawn between the two by `blend`, set every frame,
//              so 20 steps a second look like every frame
//   CUSTOM.z   which way it faces (0 right, 1 left, 2 down, 3 up) plus its
//              own phase, 0-1, so a crowd does not hop in step
//   CUSTOM.w   the element's hue, 0-1 (Element.hue_for() / 360)
//   COLOR.r    how white it flashes, 0-1, when hit
//   COLOR.g    0 alive; above 0, how far through dying (0-1]
//   COLOR.a    0 for a cell nobody holds - it draws nothing
//
// swarm.gd keeps the facing, so one standing still keeps the way it last
// went.
//
// THE RECOLOUR is element_recolour.gdshader's: the hue replaced, shading kept,
// greys left alone. Copied rather than shared because a canvas shader cannot
// include another's fragment() - keep the two in step.
shader_type canvas_item;

uniform float blend : hint_range(0.0, 1.0) = 1.0;
// Sheet size in px, and where each facing's rows start (walk; death is a row
// below it). Right, left, down, up - the order swarm.gd's ROWS uses.
uniform vec2 sheet = vec2(432.0, 1824.0);
uniform vec4 walk_rows = vec4(1152.0, 1344.0, 1536.0, 1728.0);
uniform float cell = 48.0;
uniform float walk_frames = 9.0;
// Frames a second: the Field's small slime walks at 5 (its smallwalk rows).
// At 9 the crowd squashed and stretched twice as fast as any slime, which
// read as wobbling.
uniform float walk_speed = 5.0;
uniform float death_frames = 5.0;
// A little brighter than drawn: the crypt is dark, and a crowd of small
// slimes in it read as a shadow.
uniform float brightness = 1.35;

varying vec2 v_cell;      // the cell's top left corner on the sheet, px
varying float v_flash;
varying float v_hue;
varying float v_alpha;

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

void vertex() {
	// Drawn between the last step and this one.
	VERTEX += INSTANCE_CUSTOM.xy * (1.0 - blend);
	float facing = floor(INSTANCE_CUSTOM.z);
	float phase = fract(INSTANCE_CUSTOM.z);
	float row = facing < 0.5 ? walk_rows.x : (facing < 1.5 ? walk_rows.y : (facing < 2.5 ? walk_rows.z : walk_rows.w));
	float frame;
	float dying = COLOR.g;
	if (dying > 0.0) {
		row += cell;
		frame = min(death_frames - 1.0, floor(dying * death_frames));
	} else {
		frame = mod(floor(TIME * walk_speed + phase * walk_frames), walk_frames);
	}
	v_cell = vec2(frame * cell, row);
	v_flash = COLOR.r;
	v_hue = INSTANCE_CUSTOM.w;
	v_alpha = COLOR.a;
}

void fragment() {
	vec2 at = (v_cell + UV * cell) / sheet;
	vec4 src = texture(TEXTURE, at);
	vec3 rgb = src.rgb;
	if (src.a > 0.004) {
		vec3 hsv = rgb_to_hsv(src.rgb);
		if (hsv.y >= 0.08) {
			rgb = hsv_to_rgb(vec3(v_hue, hsv.y, hsv.z));
		}
	}
	rgb = mix(rgb * brightness, vec3(1.0), v_flash);
	COLOR = vec4(rgb, src.a * v_alpha);
}
