shader_type canvas_item;

// Row-shift + RGB split + scan tear glitch — extended from ASCII Live Visuals Engine.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 3.0) = 0.85;
uniform float rate : hint_range(0.1, 8.0) = 1.5;
uniform float h_size : hint_range(0.05, 1.0) = 0.75;
uniform float rgb_split : hint_range(0.0, 1.0) = 0.85;
uniform float slice_chaos : hint_range(0.0, 1.0) = 0.65;
uniform float audio_drive : hint_range(0.0, 2.0) = 0.0;
uniform float time_sec = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float drive = clamp(intensity + audio_drive * 0.55, 0.0, 3.0);
	float t = time_sec * rate;

	float band = floor(uv.y * (6.0 + h_size * 22.0));
	float h = hash21(vec2(band, floor(t * 3.0)));
	float shift = 0.0;
	if (h < 0.28 + drive * 0.45) {
		shift = (hash21(vec2(band * 1.7, floor(t * 7.0))) - 0.5) * 0.28 * drive * (0.45 + h_size);
	}

	float vband = floor(uv.x * (4.0 + slice_chaos * 14.0));
	float vh = hash21(vec2(vband, floor(t * 2.2)));
	float vshift = 0.0;
	if (vh < 0.16 + drive * slice_chaos * 0.45) {
		vshift = (hash21(vec2(vband * 2.3, floor(t * 5.0))) - 0.5) * 0.18 * drive * slice_chaos;
	}

	vec2 base_uv = uv + vec2(shift, vshift);
	vec2 uv_r = base_uv + vec2(rgb_split * 0.04 * drive, 0.0);
	vec2 uv_g = base_uv;
	vec2 uv_b = base_uv - vec2(rgb_split * 0.045 * drive, 0.0);

	float r = textureLod(screen_texture, clamp(uv_r, vec2(0.001), vec2(0.999)), 0.0).r;
	float g = textureLod(screen_texture, clamp(uv_g, vec2(0.001), vec2(0.999)), 0.0).g;
	float b = textureLod(screen_texture, clamp(uv_b, vec2(0.001), vec2(0.999)), 0.0).b;
	vec3 src = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 glitched = vec3(r, g, b);

	float block = hash21(vec2(floor(uv.x * 14.0), floor(uv.y * 10.0) + floor(t * 2.0)));
	if (block < (0.06 + slice_chaos * 0.1) * drive) {
		vec2 buv = uv + vec2((block - 0.02) * 0.85, (hash21(vec2(block, t)) - 0.5) * 0.14 * slice_chaos);
		glitched = textureLod(screen_texture, clamp(buv, vec2(0.001), vec2(0.999)), 0.0).rgb;
	}

	float scan = step(0.9, hash21(vec2(floor(uv.y * 90.0), floor(t * 18.0))));
	glitched = mix(glitched, vec3(1.0), scan * 0.45 * drive * slice_chaos);

	float mix_amt = clamp(drive * 0.85, 0.0, 1.0);
	COLOR = vec4(mix(src, glitched, mix_amt), 1.0);
}
