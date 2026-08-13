shader_type canvas_item;

// Reaction-diffusion overlay. Tints the live frame — never replaces it with black.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D rd_tex : filter_linear, repeat_enable;
uniform float mix_amount : hint_range(0.0, 1.0) = 0.55;
uniform vec3 color_low : source_color = vec3(0.20, 0.62, 0.98);
uniform vec3 color_high : source_color = vec3(1.0, 0.38, 0.72);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src = textureLod(screen_texture, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
	vec2 rd = texture(rd_tex, uv).rg;
	float v = clamp(rd.g * 1.65, 0.0, 1.0);
	vec3 pattern = mix(color_low, color_high, v);
	float lum = dot(src, vec3(0.299, 0.587, 0.114));
	vec3 lit = pattern * (0.28 + lum * 0.95) + src * 0.35;
	float m = clamp(mix_amount, 0.0, 1.0) * (0.12 + v * 0.88);
	vec3 outc = mix(src, max(lit, src * 0.55), m);
	COLOR = vec4(outc, 1.0);
}
