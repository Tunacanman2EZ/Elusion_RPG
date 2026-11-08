// riftvoid.gdshader - THE RIFT'S VOID in one draw (0.134.4; crownedrift.gd).
// It was a rect, 56 cloud discs and 260 star dots drawn one by one, every
// frame: half the Crowned room's draws. Here the same picture is worked out
// per pixel - the deep indigo, the seven lands' clouds (each four discs at
// 0.035, drifting as before), and the stars, one in some of each STAR_CELL
// square, glimmering at their own speeds.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 origin = vec2(0.0);
uniform float clock = 0.0;
// Each cloud: x, y where it is now (crownedrift.gd moves them, so no pixel
// works out a drift), and its size squared.
uniform vec4 cloud_spot[14];
uniform vec4 cloud_colour[14];
uniform int clouds = 14;
uniform float star_cell = 160.0;
uniform float star_share = 0.49;

varying vec2 world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world = VERTEX + origin;
}

void fragment() {
	vec3 c = vec3(0.06, 0.035, 0.11);
	for (int k = 0; k < clouds; k++) {
		vec4 spot = cloud_spot[k];
		vec2 off = world - spot.xy;
		float d2 = dot(off, off);
		if (d2 < spot.z) {
			// Inside the outer disc: one mix for each of the four it is in
			// (sizes 1, 0.8, 0.6, 0.4 of the outer, squared).
			float rings = 1.0 + step(d2, spot.z * 0.64) + step(d2, spot.z * 0.36) + step(d2, spot.z * 0.16);
			c = mix(c, cloud_colour[k].rgb, 1.0 - pow(0.965, rings));
		}
	}
	vec2 cell = floor(world / star_cell);
	if (hash12(cell) < star_share) {
		vec2 at = (cell + 0.05 + vec2(hash12(cell + 17.0), hash12(cell + 41.0)) * 0.9) * star_cell;
		float n = floor(hash12(cell + 73.0) * 15.0);
		float radius = 1.0 + mod(n, 3.0) * 0.4;
		float speed = 1.3 + mod(n, 5.0) * 0.4;
		float glimmer = 0.35 + 0.35 * sin(clock * speed + hash12(cell + 97.0) * 6.2831853);
		if (distance(world, at) < radius) {
			c = mix(c, vec3(0.9, 0.85, 1.0), glimmer);
		}
	}
	COLOR = vec4(c, 1.0);
}
