shader_type canvas_item;

// Real-ish pixel sorting: thresholded horizontal spans sorted by luminance rank.
// Each fragment finds its contiguous in-threshold span, counts how many pixels in
// the span are darker (rank), then samples the pixel at start+rank — classic
// Kim Asendorf / datamosh look without a full GPU sort network.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float intensity : hint_range(0.0, 3.0) = 0.85;
uniform float threshold : hint_range(0.0, 1.0) = 0.35;
uniform float stretch : hint_range(0.05, 1.0) = 0.55;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;
uniform float time_sec = 0.0;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

bool sortable(float lum, float thr) {
	return lum >= thr;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = vec2(1.0) / vec2(textureSize(screen_texture, 0));
	vec3 src = textureLod(screen_texture, uv, 0.0).rgb;
	float lum = luma(src);

	float drive = clamp(intensity + audio_drive * 0.55, 0.0, 3.0);
	float thr = clamp(threshold - audio_drive * 0.08, 0.0, 0.95);
	int max_span = int(clamp(12.0 + stretch * 96.0 + drive * 24.0, 16.0, 128.0));

	if (!sortable(lum, thr) || drive < 0.02) {
		COLOR = vec4(src, 1.0);
		return;
	}

	// Walk left/right while above threshold to find span bounds (in pixels).
	int left = 0;
	for (int i = 1; i <= 128; i++) {
		if (i > max_span) {
			break;
		}
		vec2 suv = uv - vec2(px.x * float(i), 0.0);
		if (suv.x < 0.0) {
			break;
		}
		float sl = luma(textureLod(screen_texture, suv, 0.0).rgb);
		if (!sortable(sl, thr)) {
			break;
		}
		left = i;
	}
	int right = 0;
	for (int i = 1; i <= 128; i++) {
		if (i > max_span) {
			break;
		}
		vec2 suv = uv + vec2(px.x * float(i), 0.0);
		if (suv.x > 1.0) {
			break;
		}
		float sl = luma(textureLod(screen_texture, suv, 0.0).rgb);
		if (!sortable(sl, thr)) {
			break;
		}
		right = i;
	}

	int span = left + right + 1;
	if (span < 3) {
		COLOR = vec4(src, 1.0);
		return;
	}

	// Rank = how many pixels in the span are darker than this one (brightness sort).
	int rank = 0;
	for (int i = -left; i <= right; i++) {
		vec2 suv = uv + vec2(px.x * float(i), 0.0);
		float sl = luma(textureLod(screen_texture, suv, 0.0).rgb);
		if (sl < lum - 0.0001) {
			rank += 1;
		} else if (abs(sl - lum) <= 0.0001 && i < 0) {
			// Stable tie-break: earlier pixels with equal luma keep lower rank.
			rank += 1;
		}
	}

	int dest_offset = rank - left;
	vec2 sorted_uv = uv + vec2(px.x * float(dest_offset), 0.0);
	sorted_uv = clamp(sorted_uv, vec2(0.001), vec2(0.999));
	vec3 sorted = textureLod(screen_texture, sorted_uv, 0.0).rgb;

	float mix_amt = clamp(drive * 0.85, 0.0, 1.0);
	COLOR = vec4(mix(src, sorted, mix_amt), 1.0);
}
