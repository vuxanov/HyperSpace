shader_type canvas_item;

// Screen-space chromatic aberration (RGB channel offset) — strong defaults.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 3.0) = 0.85;
uniform float amount : hint_range(0.0, 3.0) = 1.0;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);
	float drive = clamp(intensity * amount + audio_drive * 0.45, 0.0, 4.0);
	float offset = drive * 0.055 * (0.35 + dist * 1.8);
	vec2 dir = normalize(centered + vec2(0.0001));

	float r = textureLod(screen_texture, clamp(uv + dir * offset, vec2(0.001), vec2(0.999)), 0.0).r;
	float g = textureLod(screen_texture, uv, 0.0).g;
	float b = textureLod(screen_texture, clamp(uv - dir * offset, vec2(0.001), vec2(0.999)), 0.0).b;
	COLOR = vec4(r, g, b, 1.0);
}
