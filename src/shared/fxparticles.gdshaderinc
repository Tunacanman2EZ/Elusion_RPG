// fxparticles.gdshaderinc - the particle drawer's shader, included by
// fxparticles.gdshader (lit) and fxparticles_unshaded.gdshader (unshaded: a
// CanvasItemMaterial's LIGHT_MODE_UNSHADED, the frost's glints). What it
// does is said at the top of fxparticles.gdshader.

uniform float now = 0.0;
uniform sampler2D params : filter_nearest;
uniform sampler2D ramps : filter_nearest;
// The texture's size in px (1 x 1 with none: a square of scale px).
uniform vec2 tex_size = vec2(1.0, 1.0);
uniform bool textured = false;

varying vec4 v_colour;
varying vec2 v_uv;

vec4 p(int k, int row) {
	return texelFetch(params, ivec2(k, row), 0);
}

// Where a glide is at `when`, in the emitter's own axes.
vec2 glide_at(vec4 g, float start, float when) {
	float tau = clamp((when - start) / g.z, 0.0, 1.0);
	return g.xy * (1.0 - pow(tau, g.w));
}

vec4 ramp(int row, float at) {
	int x = clamp(int(at * 31.0 + 0.5), 0, 31);
	return texelFetch(ramps, ivec2(x, row), 0);
}

// A particle's numbers, 0-1, from its seed: no sine.
float roll(float seed, float which) {
	float q = fract((seed + which * 17.17) * 0.1031);
	q *= q + 33.33;
	q *= q + q;
	return fract(q);
}

void vertex() {
	int row = int(INSTANCE_CUSTOM.y + 0.5);
	vec4 p0 = p(0, row);
	vec4 p1 = p(1, row);
	float amount = p0.x;
	float life = max(p0.y, 0.001);
	float index = floor(UV.x);
	vec2 corner = vec2(fract(UV.x) * 2.0 - 1.0, UV.y * 2.0 - 1.0);
	float t0 = MODEL_MATRIX[2].x;
	float t1 = MODEL_MATRIX[2].y;
	// When in its cycle this particle comes out: spread over the lifetime,
	// all at once as explosiveness nears 1.
	float phase = index / max(amount, 1.0) * (1.0 - p0.w);
	float since = now - t0 - phase * life;
	float cycle = floor(since / life);
	float age = since - cycle * life;
	float born = now - age;
	float seed = INSTANCE_CUSTOM.x * 1.371 + index * 7.31 + cycle * 3.17;
	float own_life = life * (1.0 - roll(seed, 1.0) * p0.z);
	bool hidden = index >= amount || since < 0.0 || born > t1 + 0.0001 || age >= own_life
		|| (p1.x > 0.5 && cycle > 0.5) || COLOR.a <= 0.0;
	if (hidden) {
		VERTEX = vec2(0.0);
		v_colour = vec4(0.0);
		v_uv = vec2(0.0);
	} else {
		vec4 p2 = p(2, row);
		vec4 p3 = p(3, row);
		vec4 p4 = p(4, row);
		vec4 p5 = p(5, row);
		vec4 p6 = p(6, row);
		vec4 p7 = p(7, row);
		float t = age;
		// Where it comes out, as CPUParticles2D rolls it: a point; a disc, its
		// distance from the middle even (so more near the middle); a sphere's
		// surface seen from above (a disc, more near its rim); a box.
		vec2 from = vec2(0.0);
		int shape = int(p1.y + 0.5);
		if (shape == 1) {
			float a = roll(seed, 2.0) * 6.2831853;
			from = vec2(cos(a), sin(a)) * roll(seed, 3.0) * p1.z;
		} else if (shape == 2) {
			float a = roll(seed, 2.0) * 6.2831853;
			float h = roll(seed, 3.0);
			from = vec2(cos(a), sin(a)) * sqrt(1.0 - h * h) * p1.z;
		} else if (shape == 3) {
			from = vec2(roll(seed, 2.0) * 2.0 - 1.0, roll(seed, 3.0) * 2.0 - 1.0) * vec2(p1.w, p2.x);
		}
		// Its way and speed.
		float base = atan(p2.z, p2.y);
		float a = base + (roll(seed, 4.0) * 2.0 - 1.0) * p2.w;
		vec2 way = vec2(cos(a), sin(a));
		float speed = mix(p3.x, p3.y, roll(seed, 5.0));
		// Gravity in the emitter's axes: its own with local_coords, else the
		// world's turned back into them.
		mat2 basis = mat2(MODEL_MATRIX[0].xy, MODEL_MATRIX[1].xy);
		bool in_world = p5.z < 0.5;
		vec2 fall = p4.xy;
		if (in_world && abs(determinant(basis)) > 0.000001) {
			fall = inverse(basis) * p4.xy;
		}
		// Turning round the emitter's middle (CPUParticles2D's clockwise
		// matrix, so this way round): where it came out turned, and its
		// speed and gravity carried round as they push it - the closed form
		// of turning a little and moving a little every frame.
		float w = -mix(p4.z, p4.w, roll(seed, 7.0)) * 6.2831853;
		vec2 at;
		if (abs(w) > 0.0001) {
			float c = cos(w * t);
			float s = sin(w * t);
			mat2 turned = mat2(vec2(c, s), vec2(-s, c));
			mat2 swept = mat2(vec2(s / w, (1.0 - c) / w), vec2(-(1.0 - c) / w, s / w));
			float int_cos = t * s / w + (c - 1.0) / (w * w);
			float int_sin = -t * c / w + s / (w * w);
			mat2 weighted = mat2(vec2(int_cos, int_sin), vec2(-int_sin, int_cos));
			at = turned * from + swept * (way * speed) + (t * swept - weighted) * fall;
		} else {
			// Slowing (damping) as it goes, and pulled by gravity.
			float damp = mix(p3.z, p3.w, roll(seed, 6.0));
			float run;
			if (damp > 0.0) {
				float stop = min(t, speed / damp);
				run = speed * stop - 0.5 * damp * stop * stop;
			} else {
				run = speed * t;
			}
			at = from + way * run + 0.5 * fall * t * t;
		}
		// Gliding, where the glide was (left in the world: when it came out);
		// left behind in the world otherwise, where the emitter was when it
		// came out, from how fast it is moving.
		if (p7.z > 0.0) {
			at += glide_at(p7, t0 + COLOR.b, in_world ? born : now);
		} else if (in_world) {
			vec2 behind = -COLOR.rg * t;
			at += abs(determinant(basis)) > 0.000001 ? inverse(basis) * behind : behind;
		}
		float life_t = clamp(t / own_life, 0.0, 1.0);
		float size = mix(p5.x, p5.y, roll(seed, 8.0));
		int curve_row = int(INSTANCE_CUSTOM.w + 0.5);
		if (curve_row >= 0 && p6.w > 0.5) {
			size *= ramp(curve_row, life_t).r * 4.0;
		}
		VERTEX = at + corner * 0.5 * tex_size * size;
		v_uv = corner * 0.5 + 0.5;
		vec4 colour = ramp(int(INSTANCE_CUSTOM.z + 0.5), life_t);
		if (p6.y > 0.5) {
			colour *= ramp(int(p6.z + 0.5), roll(seed, 9.0));
		}
		colour.a *= COLOR.a;
		v_colour = colour;
	}
}

void fragment() {
	vec4 picture = textured ? texture(TEXTURE, v_uv) : vec4(1.0);
	COLOR = picture * v_colour;
}
