shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float persistence : hint_range(0.5, 0.98) = 0.88;
uniform float zoom : hint_range(0.94, 1.12) = 1.035;
uniform float mix_amount : hint_range(0.0, 1.0) = 0.72;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;
uniform vec3 tint = vec3(0.9, 0.95, 1.2);

void fragment() {
	vec2 uv = SCREEN_UV;
	float z = zoom + audio_drive * 0.05;
	vec2 centered = (uv - 0.5) / z + 0.5;
	vec2 spin = uv - 0.5;
	float ang = audio_drive * 0.04;
	float ca = cos(ang);
	float sa = sin(ang);
	spin = vec2(ca * spin.x - sa * spin.y, sa * spin.x + ca * spin.y);
	vec2 spun = spin + 0.5;
	vec3 current = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 trailed = textureLod(screen_texture, clamp(centered, vec2(0.0), vec2(1.0)), 0.0).rgb;
	vec3 swirled = textureLod(screen_texture, clamp(spun, vec2(0.0), vec2(1.0)), 0.0).rgb;
	vec3 smear = textureLod(screen_texture, uv + vec2(0.003, -0.002) * (1.0 + audio_drive * 2.0), 0.0).rgb;
	vec3 ghost = mix(mix(trailed, swirled, 0.35), smear, 0.4) * tint;
	float p = clamp(persistence + audio_drive * 0.06, 0.55, 0.97);
	vec3 result = mix(current, mix(current, ghost, p), mix_amount);
	COLOR = vec4(result, 1.0);
}
