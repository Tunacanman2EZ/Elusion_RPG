// hitflash.gdshader - the frame on screen as a solid white shape (hitflash.gd).
//
// What the artist drew in the middle of every hitflash: the pose, every
// opaque pixel pure white. The alpha is the frame's own times whatever
// fades the sprite (its modulate's alpha, which arrives in COLOR), so a
// fading body flashes fading; the colour is white whatever tints it.
shader_type canvas_item;

void fragment() {
	COLOR = vec4(1.0, 1.0, 1.0, COLOR.a);
}
