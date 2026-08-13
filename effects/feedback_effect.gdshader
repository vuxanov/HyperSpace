shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D history_tex : source_color, filter_linear_mipmap;
uniform float persistence : hint_range(0.0, 1.0) = 0.9;
uniform float opacity : hint_range(0.0, 1.0) = 0.7;
uniform float mix_amount : hint_range(0.0, 1.0) = 0.7;
uniform float zoom : hint_range(0.94, 1.12) = 1.04;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;
uniform float has_history : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint = vec3(1.02, 1.0, 1.08);

void fragment() {
	vec2 uv = SCREEN_UV;
	float z = zoom + audio_drive * 0.04;
	vec2 hist_uv = clamp((uv - 0.5) / z + 0.5, vec2(0.001), vec2(0.999));
	vec3 scene = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 hist = textureLod(history_tex, hist_uv, 1.15).rgb * tint;

	float p = clamp(persistence, 0.0, 1.0);
	float op = clamp(max(opacity, mix_amount), 0.0, 1.0) * has_history;

	vec3 faded = hist * p;
	vec3 live = scene * (0.14 + 0.16 * p);
	vec3 trail = max(faded, live);
	float keep = step(0.0001, p);
	trail *= keep;

	float lum = max(max(trail.r, trail.g), trail.b);
	float a = op * smoothstep(0.035, 0.26, lum);
	COLOR = vec4(trail, a);
}
