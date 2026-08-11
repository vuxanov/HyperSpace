shader_type canvas_item;

// Row-shift + RGB split. No early `return` in fragment (Godot 4.7 rejects it).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float rate : hint_range(0.1, 12.0) = 2.0;
uniform float h_size : hint_range(0.05, 1.0) = 0.8;
uniform float rgb_split : hint_range(0.0, 1.0) = 0.7;
uniform float slice_chaos : hint_range(0.0, 1.0) = 0.55;
uniform float audio_drive : hint_range(0.0, 3.0) = 0.0;
uniform float time_sec = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 sample_screen(vec2 uv) {
	return textureLod(screen_texture, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src = sample_screen(uv);
	float drive = clamp(intensity * 0.85 + audio_drive * 0.9, 0.0, 3.5);

	float t = time_sec * rate;
	float band = floor(uv.y * (6.0 + h_size * 24.0));
	float h = hash21(vec2(band, floor(t * 3.0)));
	float shift = 0.0;
	if (h < 0.32 + drive * 0.45) {
		shift = (hash21(vec2(band * 1.7, floor(t * 7.0))) - 0.5) * 0.35 * drive * (0.45 + h_size);
	}

	float vband = floor(uv.x * (3.0 + slice_chaos * 14.0));
	float vh = hash21(vec2(vband, floor(t * 2.2)));
	float vshift = 0.0;
	if (vh < 0.18 + drive * slice_chaos * 0.45) {
		vshift = (hash21(vec2(vband * 2.3, floor(t * 5.0))) - 0.5) * 0.22 * drive * slice_chaos;
	}

	vec2 base_uv = uv + vec2(shift, vshift);
	float split = rgb_split * 0.08 * drive;
	float r = sample_screen(base_uv + vec2(split, 0.0)).r;
	float g = sample_screen(base_uv).g;
	float b = sample_screen(base_uv - vec2(split * 1.05, 0.0)).b;
	vec3 glitched = vec3(r, g, b);

	float block = hash21(vec2(floor(uv.x * 10.0), floor(uv.y * 8.0) + floor(t * 2.0)));
	if (block < (0.06 + slice_chaos * 0.12) * drive) {
		vec2 buv = uv + vec2((block - 0.02) * 0.9, (hash21(vec2(block, t)) - 0.5) * 0.12 * slice_chaos);
		glitched = sample_screen(buv);
	}

	float mix_amt = clamp(0.35 + drive * 0.4, 0.0, 0.92) * step(0.02, drive);
	COLOR = vec4(mix(src, glitched, mix_amt), 1.0);
}
