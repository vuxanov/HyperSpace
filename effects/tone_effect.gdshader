shader_type canvas_item;

// Image tone: brightness, contrast, invert, then saturation (Rec.709 luminance).
// Order: brightness → contrast → invert → saturation. Saturation 0 = grayscale, 1 = unchanged, >1 = punchier.
// No early `return` in fragment (Godot 4.7 rejects it).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float invert_amount : hint_range(0.0, 1.0) = 0.0;
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float contrast : hint_range(0.0, 4.0) = 1.0;
uniform float saturation : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	vec3 src = textureLod(screen_texture, clamp(SCREEN_UV, vec2(0.001), vec2(0.999)), 0.0).rgb;
	vec3 c = src * max(brightness, 0.0);
	c = (c - vec3(0.5)) * max(contrast, 0.0) + vec3(0.5);
	c = mix(c, vec3(1.0) - c, clamp(invert_amount, 0.0, 1.0));
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(lum), c, max(saturation, 0.0));
	COLOR = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}
