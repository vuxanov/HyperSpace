shader_type canvas_item;

// Lightweight threshold streak / sort. No early `return` in fragment (Godot 4.7 rejects it).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 3.0) = 0.75;
uniform float threshold : hint_range(0.0, 1.0) = 0.45;
uniform float stretch : hint_range(0.05, 1.0) = 0.55;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;
uniform float time_sec = 0.0;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 sample_screen(vec2 uv) {
	return textureLod(screen_texture, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src = sample_screen(uv);

	float drive = clamp(intensity + audio_drive * 0.7, 0.0, 2.5);
	float lum = luma(src);
	float thr = clamp(threshold - audio_drive * 0.08, 0.05, 0.95);
	float active = step(0.02, drive) * step(thr, lum);

	vec2 px = max(SCREEN_PIXEL_SIZE, vec2(0.0005));
	float span = (8.0 + stretch * 28.0 + drive * 10.0);
	float dir = (fract(sin(dot(floor(uv * vec2(1.0 / px.x, 1.0)), vec2(12.9898, 78.233)) + time_sec) * 43758.5453) > 0.5) ? 1.0 : -1.0;

	vec3 a = sample_screen(uv + vec2(px.x * span * 0.25 * dir, 0.0));
	vec3 b = sample_screen(uv + vec2(px.x * span * 0.55 * dir, 0.0));
	vec3 c = sample_screen(uv + vec2(px.x * span * dir, 0.0));

	vec3 sorted = src;
	if (luma(a) > lum) {
		sorted = a;
	}
	if (luma(b) > luma(sorted)) {
		sorted = b;
	}
	if (luma(c) < thr) {
		sorted = mix(sorted, src, 0.35);
	}

	float streak = stretch * drive * 0.4;
	vec3 pull = sample_screen(uv - vec2(px.x * streak * 14.0, 0.0));
	sorted = mix(sorted, pull, clamp(streak * 0.45, 0.0, 0.5));

	float mix_amt = clamp(0.3 + drive * 0.4, 0.0, 0.9) * active;
	COLOR = vec4(mix(src, sorted, mix_amt), 1.0);
}
