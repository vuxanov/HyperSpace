shader_type canvas_item;

// Chromatic aberration. No early `return` in fragment (Godot 4.7 rejects it).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float amount : hint_range(0.0, 4.0) = 1.2;
uniform float audio_drive : hint_range(0.0, 3.0) = 0.0;

vec3 sample_screen(vec2 uv) {
	return textureLod(screen_texture, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src = sample_screen(uv);

	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);
	float drive = clamp(intensity * amount * 0.55 + audio_drive * 0.75, 0.0, 4.0);
	float active = step(0.02, drive);

	float offset = drive * 0.055 * (0.2 + dist * 1.8) * active;
	vec2 dir = normalize(centered + vec2(0.0001));
	float r = sample_screen(uv + dir * offset).r;
	float g = src.g;
	float b = sample_screen(uv - dir * offset).b;
	COLOR = vec4(mix(src, vec3(r, g, b), active), 1.0);
}
