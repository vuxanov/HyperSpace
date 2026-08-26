shader_type canvas_item;

// Pixel-accurate slice shift + RGB split. v_size / h_size are pixels (1 = 1 px).
// Slice chaos randomizes layout; rate only drives animation speed.
// No early `return` in fragment (Godot 4.7 rejects it).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 8.0) = 1.2;
uniform float rate : hint_range(0.0, 64.0) = 2.0;
uniform float v_size : hint_range(1.0, 512.0) = 24.0;
uniform float h_size : hint_range(1.0, 512.0) = 48.0;
uniform float rgb_split : hint_range(0.0, 1.0) = 0.7;
uniform float slice_chaos : hint_range(0.0, 1.0) = 0.4;
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
	float chaos = clamp(slice_chaos, 0.0, 1.0);

	vec2 px = max(SCREEN_PIXEL_SIZE, vec2(1.0 / 16384.0));
	float slice_h = max(v_size, 1.0) * px.y;
	float slice_w = max(h_size, 1.0) * px.x;

	float t = time_sec * max(rate, 0.0);
	// Layout clock is independent of Speed so chaos does not look like a faster rate.
	float layout_t = floor(time_sec * mix(0.0, 1.8, chaos));

	float y0 = uv.y / slice_h;
	float x0 = uv.x / slice_w;
	float y_jit = (hash21(vec2(floor(y0), 19.7 + layout_t)) - 0.5) * chaos * 0.95;
	float x_jit = (hash21(vec2(floor(x0), 81.3 + layout_t)) - 0.5) * chaos * 0.95;
	float band = floor(y0 + y_jit);
	float vband = floor(x0 + x_jit);

	float row_stable = hash21(vec2(band, 4.1 + layout_t));
	float row_anim = hash21(vec2(band, floor(t * 3.0)));
	float row_pick = mix(row_stable, row_anim, 0.6);
	float row_mag = mix(0.7, 0.25 + hash21(vec2(band * 1.9, 12.0 + layout_t)), chaos);
	float shift = 0.0;
	if (row_pick < 0.30 + drive * 0.42) {
		shift = (hash21(vec2(band * 1.7, floor(t * 7.0))) - 0.5) * 0.32 * drive * row_mag;
	}

	float col_stable = hash21(vec2(vband, 8.2 + layout_t));
	float col_anim = hash21(vec2(vband, floor(t * 2.2)));
	float col_pick = mix(col_stable, col_anim, 0.55);
	float col_mag = mix(0.45, 0.2 + hash21(vec2(vband * 2.1, 17.0 + layout_t)), chaos);
	float vshift = 0.0;
	if (col_pick < 0.16 + drive * 0.32 * (0.35 + chaos)) {
		vshift = (hash21(vec2(vband * 2.3, floor(t * 5.0))) - 0.5) * 0.20 * drive * col_mag;
	}

	vec2 base_uv = uv + vec2(shift, vshift);
	float split = rgb_split * 0.08 * drive;
	float r = sample_screen(base_uv + vec2(split, 0.0)).r;
	float g = sample_screen(base_uv).g;
	float b = sample_screen(base_uv - vec2(split * 1.05, 0.0)).b;
	vec3 glitched = vec3(r, g, b);

	// Chaos-only mosaic blocks (off at chaos = 0).
	float block_n = hash21(vec2(floor(uv.x / slice_w), floor(uv.y / slice_h) + layout_t));
	if (block_n < 0.14 * drive * chaos) {
		vec2 buv = uv + vec2((block_n - 0.07) * 1.1, (hash21(vec2(block_n, layout_t)) - 0.5) * 0.16);
		glitched = sample_screen(buv);
	}

	float mix_amt = clamp(0.35 + drive * 0.4, 0.0, 0.92) * step(0.02, drive);
	COLOR = vec4(mix(src, glitched, mix_amt), 1.0);
}
