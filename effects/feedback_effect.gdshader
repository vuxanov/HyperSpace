shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D history_tex : source_color, filter_linear_mipmap;
uniform float persistence : hint_range(0.5, 0.98) = 0.88;
uniform float zoom : hint_range(0.94, 1.12) = 1.04;
uniform float mix_amount : hint_range(0.0, 1.0) = 0.75;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;
uniform float has_history : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint = vec3(0.95, 0.98, 1.15);

void fragment() {
	vec2 uv = SCREEN_UV;
	float z = zoom + audio_drive * 0.04;
	vec2 centered = (uv - 0.5) / z + 0.5;
	vec3 current = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 hist = textureLod(history_tex, clamp(centered, vec2(0.001), vec2(0.999)), 0.0).rgb * tint;
	float p = clamp(persistence + audio_drive * 0.05, 0.55, 0.97);
	vec3 trailed = mix(current, hist, p * has_history);
	vec3 result = mix(current, trailed, mix_amount);
	COLOR = vec4(result, 1.0);
}
