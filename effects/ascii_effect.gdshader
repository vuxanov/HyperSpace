shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D ascii_atlas : source_color, filter_nearest;
uniform float density : hint_range(1.0, 200.0) = 80.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.9;
uniform float audio_highs : hint_range(0.0, 5.0) = 0.0;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform float contrast : hint_range(0.5, 3.0) = 1.2;
uniform int charset_len = 10;
uniform float cell_aspect = 0.55; // width/height of a character cell on screen

void fragment() {
	vec2 uv = SCREEN_UV;
	float cols = max(density, 1.0);
	float rows = max(cols * cell_aspect, 1.0);
	vec2 cell = vec2(1.0 / cols, 1.0 / rows);
	vec2 cell_id = floor(uv / cell);
	vec2 cell_uv = fract(uv / cell);
	vec2 sample_uv = (cell_id + vec2(0.5)) * cell;
	vec3 src = textureLod(screen_texture, sample_uv, 0.0).rgb;
	float lum = dot(src, vec3(0.299, 0.587, 0.114));
	lum = clamp((lum - 0.5) * contrast + 0.5 + audio_highs * 0.12, 0.0, 1.0);

	float n = float(max(charset_len - 1, 1));
	float idx = floor(lum * n + 0.0001);
	idx = clamp(idx, 0.0, n);

	// Atlas is a horizontal strip of glyphs.
	float atlas_u = (idx + cell_uv.x) / float(max(charset_len, 1));
	float atlas_v = cell_uv.y;
	float glyph = texture(ascii_atlas, vec2(atlas_u, atlas_v)).a;
	// Prefer alpha; fall back to luminance of glyph RGB.
	glyph = max(glyph, texture(ascii_atlas, vec2(atlas_u, atlas_v)).r);

	vec3 ascii_col = src * tint * (0.35 + lum * 0.9);
	vec3 ink = ascii_col * glyph;
	// Dark cells stay dark; bright cells show character in source hue.
	vec3 result = mix(src, ink + src * glyph * 0.15, intensity);
	// Where glyph is empty, punch toward black for readable ASCII look.
	result = mix(result, ink, intensity * (0.55 + glyph * 0.45));
	COLOR = vec4(result, 1.0);
}
