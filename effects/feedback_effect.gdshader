shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float persistence : hint_range(0.5, 0.98) = 0.86;
uniform float zoom : hint_range(0.96, 1.08) = 1.02;
uniform float mix_amount : hint_range(0.0, 1.0) = 0.65;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;
uniform vec3 tint = vec3(0.85, 0.9, 1.15);

void fragment() {
	vec2 uv = SCREEN_UV;
	float z = zoom + audio_drive * 0.03;
	vec2 centered = (uv - 0.5) / z + 0.5;
	vec3 current = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 trailed = textureLod(screen_texture, centered, 0.0).rgb;
	// Fake temporal trail by mixing zoomed/offset samples of the current frame.
	vec3 smear = textureLod(screen_texture, uv + vec2(0.002, -0.001) * (1.0 + audio_drive), 0.0).rgb;
	vec3 ghost = mix(trailed, smear, 0.45) * tint;
	float p = clamp(persistence + audio_drive * 0.05, 0.5, 0.97);
	vec3 result = mix(current, mix(current, ghost, p), mix_amount);
	COLOR = vec4(result, 1.0);
}
