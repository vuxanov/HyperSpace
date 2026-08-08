shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float density : hint_range(10.0, 200.0) = 80.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.85;
uniform float audio_highs : hint_range(0.0, 5.0) = 0.0;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform float contrast : hint_range(0.5, 3.0) = 1.0;
uniform int preset_mode = 0; // 0 classic, 1 green, 2 amber, 3 neon, 4 blocks

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = density * 0.55;
	vec2 pixel_size = 1.0 / vec2(density, aspect);
	if (preset_mode == 4) {
		pixel_size = 1.0 / vec2(density * 0.45, density * 0.45);
	}
	vec2 grid_uv = floor(uv / pixel_size) * pixel_size;
	vec3 src = texture(screen_texture, grid_uv + pixel_size * 0.5).rgb;
	float lum = dot(src, vec3(0.299, 0.587, 0.114));
	lum = clamp((lum - 0.5) * contrast + 0.5 + audio_highs * 0.1, 0.0, 1.0);

	vec3 palette;
	if (preset_mode == 1) {
		palette = vec3(0.05, lum, 0.12);
	} else if (preset_mode == 2) {
		palette = vec3(lum, lum * 0.7, 0.12);
	} else if (preset_mode == 3) {
		palette = vec3(lum, 0.2 + lum * 0.4, 1.0 - lum * 0.3);
	} else if (preset_mode == 4) {
		float stepped = floor(lum * 4.0) / 4.0;
		palette = vec3(stepped);
	} else {
		float stepped = floor(lum * 7.0) / 7.0;
		palette = vec3(stepped);
	}

	vec3 result = mix(src, palette * tint, intensity);
	COLOR = vec4(result, 1.0);
}
