// spikesparks.gdshader - every boss spike's burst of sparks in one draw
// (spikefx.gd, 0.137.5). Nothing here is art: each spark is a small square
// of its element's colour, as the CPUParticles2D each spike used to make drew
// them (no texture: a 1 px quad, scaled).
//
// ONE INSTANCE A BURST, ONE QUAD OF ITS MESH A SPARK (UV.x is the spark's
// number, VERTEX the quad's corner). The instance's transform is where the
// spike stood; its custom data, written once when the spike erupts:
//
//   CUSTOM.x   when it burst, on spikefx.gd's clock, mod WRAP
//   CUSTOM.y   its element (Element.Type), plus 16 times the burst's own
//              number (0-127) that its sparks are rolled from
//   CUSTOM.zw  half the size of the patch the sparks start in
//
// Every spark's start, angle, speed and size come from the burst and its own
// number, the way CPUParticles2D rolled them - a patch of the floor, up and
// spread by the element's angle, its speed and size between the element's
// least and most - and it flies under the element's gravity: where it is at
// any age is worked out here, so a burst is never written again. The colour
// is the old ramp: lighter than the element, then the element at 0.8, then
// half of it, gone.
//
// The element's numbers are bossprojectile.gd's ELEMENT_SPARKS, set as the
// tables below by spikefx.gd the first time an element bursts.
shader_type canvas_item;

uniform float now_mod = 0.0;
// gravity x, gravity y, least speed, most speed
uniform vec4 motion[10];
// least size, most size, life in seconds, spread either side of up (radians)
uniform vec4 shape[10];
// the element's colour; a = how many sparks a burst has
uniform vec4 tint[10];
const float WRAP = 16.0;

varying vec4 v_colour;

// A spark's numbers, 0-1, from its seed: no sine (cheap on any GPU, and the
// same on all of them).
float roll(float seed, float which) {
	float p = fract((seed + which * 17.17) * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void vertex() {
	float packed = floor(INSTANCE_CUSTOM.y + 0.5);
	int element = clamp(int(mod(packed, 16.0)), 0, 9);
	float burst_no = floor(packed / 16.0);
	float age = mod(now_mod - INSTANCE_CUSTOM.x + WRAP, WRAP);
	vec4 m = motion[element];
	vec4 s = shape[element];
	vec4 c = tint[element];
	float spark = UV.x;
	if (spark >= c.a || age >= s.z) {
		VERTEX = vec2(0.0);
		v_colour = vec4(0.0);
	} else {
		float seed = fract(burst_no * 0.6180339 + INSTANCE_CUSTOM.x * 0.1372) * 97.0 + spark * 1.731;
		vec2 from = vec2(roll(seed, 1.0) * 2.0 - 1.0, roll(seed, 2.0) * 2.0 - 1.0) * INSTANCE_CUSTOM.zw;
		float angle = -1.5707963 + (roll(seed, 3.0) * 2.0 - 1.0) * s.w;
		float speed = mix(m.z, m.w, roll(seed, 4.0));
		float size = mix(s.x, s.y, roll(seed, 5.0));
		vec2 at = from + vec2(cos(angle), sin(angle)) * speed * age + 0.5 * m.xy * age * age;
		VERTEX = at + VERTEX * size;
		float t = age / s.z;
		vec4 first = vec4(min(c.rgb + 0.35, vec3(1.0)), 1.0);
		vec4 middle = vec4(c.rgb, 0.8);
		vec4 last = vec4(c.rgb * 0.5, 0.0);
		v_colour = t < 0.45 ? mix(first, middle, t / 0.45) : mix(middle, last, (t - 0.45) / 0.55);
	}
}

void fragment() {
	COLOR = v_colour;
}
