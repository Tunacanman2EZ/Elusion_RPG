// hearth_warm.gdshader — makes a firepit's STONE glow with the fire in it,
// without touching the flame the artist drew.
//
// WHY NOT JUST modulate THE SPRITE
// --------------------------------
// modulate multiplies the whole node. Warming the ring that way warms the
// flame too, and the flame is the one part of this sprite that is already
// exactly the colour it should be — pushing it further orange flattens the
// yellow-to-red range inside it into one tone. The interesting half of "the
// fire is lit" is the cold grey stone catching the light, and that is the half
// modulate cannot reach on its own.
//
// HOW THE TWO HALVES ARE TOLD APART
// ---------------------------------
// By saturation, measured off the real sheet rather than guessed. Every opaque
// pixel in art/images/firepit.png falls into one of two bands, per 32x32 frame:
//
//     0.10 - 0.25 saturation   ~160 px   the stone ring
//     0.45 - 1.00 saturation   ~110 px   the flame
//     0.25 - 0.45 saturation    8-20 px  almost nothing lives here
//
// That empty middle is what makes a single threshold safe. 0.35 sits in the
// gap with room either side, so no amount of animation frame-to-frame drift
// moves a stone pixel across it or a flame pixel back.
shader_type canvas_item;

// 0 is cold stone, 1 is fully lit. Drive it: firepit.gd tweens it up over the
// kindle and back down when the fire goes out, which is what turns "the bricks
// warm up" into something you watch rather than a state that flips.
uniform float warmth : hint_range(0.0, 1.0) = 0.0;

// The colour the stone is being lit BY. Multiplied over it, so this reads as
// firelight falling on rock rather than as rock that has been repainted.
uniform vec4 warm_tint : source_color = vec4(1.0, 0.68, 0.42, 1.0);

// Light the stone EMITS once hot, added on top of the tint. Without this the
// multiply alone only ever darkens, and a hot stone that is dimmer than a cold
// one is the opposite of the effect.
uniform float lift : hint_range(0.0, 1.0) = 0.30;

// Saturation at or above which a pixel is flame and is left alone. See the
// measured bands above before moving this.
uniform float stone_threshold : hint_range(0.0, 1.0) = 0.35;


void fragment() {
	vec4 src = texture(TEXTURE, UV);

	if (src.a < 0.004) {
		COLOR = src;
	} else {
		float mx = max(src.r, max(src.g, src.b));
		float mn = min(src.r, min(src.g, src.b));
		float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;

		if (sat >= stone_threshold) {
			// The flame, exactly as authored.
			COLOR = src;
		} else {
			vec3 lit = src.rgb * warm_tint.rgb + warm_tint.rgb * lift;
			COLOR = vec4(mix(src.rgb, clamp(lit, 0.0, 1.0), warmth), src.a);
		}
	}
}
