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
// 0 = no blur pass, 1:1 history. BLUR_MAX_LOD * 0.35 == the old hardcoded 1.15.
uniform float blur : hint_range(0.0, 1.0) = 0.35;
// How the previous frame is composited onto the live one. 0 = Normal (the original look).
uniform int blend_mode : hint_range(0, 4) = 0;
uniform vec3 tint = vec3(1.02, 1.0, 1.08);

const float BLUR_MAX_LOD = 3.3;
const float BLUR_MAX_SPREAD = 0.006;
const float MOTION_LO = 0.018;

const int BLEND_NORMAL = 0;
const int BLEND_BRIGHTEST = 1;
const int BLEND_DARKEST = 2;
const int BLEND_EDGES = 3;
const int BLEND_CONTRAST = 4;

vec3 overlay_blend(vec3 base, vec3 top) {
	vec3 lo = 2.0 * base * top;
	vec3 hi = vec3(1.0) - 2.0 * (vec3(1.0) - base) * (vec3(1.0) - top);
	return mix(lo, hi, step(vec3(0.5), base));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 scene = textureLod(screen_texture, uv, 0.0).rgb;
	float p = clamp(persistence, 0.0, 1.0);
	float op = clamp(max(opacity, mix_amount), 0.0, 1.0) * has_history;
	float b = clamp(blur, 0.0, 1.0);

	vec3 hist;
	if (b < 0.001) {
		hist = textureLod(history_tex, uv, 0.0).rgb;
	} else {
		float z = zoom + audio_drive * 0.04;
		vec2 hist_uv = clamp((uv - 0.5) / z + 0.5, vec2(0.001), vec2(0.999));
		float lod = b * BLUR_MAX_LOD;
		float spread = b * BLUR_MAX_SPREAD;
		hist = textureLod(history_tex, hist_uv, lod).rgb;
		if (spread > 0.0) {
			vec3 ring = textureLod(history_tex, clamp(hist_uv + vec2(spread, 0.0), vec2(0.001), vec2(0.999)), lod).rgb;
			ring += textureLod(history_tex, clamp(hist_uv - vec2(spread, 0.0), vec2(0.001), vec2(0.999)), lod).rgb;
			ring += textureLod(history_tex, clamp(hist_uv + vec2(0.0, spread), vec2(0.001), vec2(0.999)), lod).rgb;
			ring += textureLod(history_tex, clamp(hist_uv - vec2(0.0, spread), vec2(0.001), vec2(0.999)), lod).rgb;
			hist = mix(hist, (hist + ring) * 0.2, b);
		}
		hist *= tint;
	}

	// Blur 0 + Normal: leftover stamps of the previous final composite (ASCII
	// included when that effect is on). ColorRect sits on that live image.
	// Compare chroma (max-min), not luma: brighter-wins freezes bright walls
	// and washes the flythrough white. Saturated "windows" (characters, props)
	// stamp; dull walls follow the live frame. Persist scales stamp lifetime.
	if (b < 0.001 && blend_mode == BLEND_NORMAL) {
		float motion = step(MOTION_LO, length(scene - hist));
		float hist_l = max(hist.r, max(hist.g, hist.b));
		float scene_l = max(scene.r, max(scene.g, scene.b));
		float sat_h = hist_l - min(hist.r, min(hist.g, hist.b));
		float sat_s = scene_l - min(scene.r, min(scene.g, scene.b));
		float keep_dark = step(hist_l + 0.04, scene_l);
		float keep_color = step(0.10, sat_h) * step(sat_s + 0.03, sat_h);
		float leftover = motion * max(keep_dark, keep_color);
		COLOR = vec4(hist, op * leftover * p);
	} else {
		vec3 faded = hist * p;
		vec3 live = scene * (0.14 + 0.16 * p);
		vec3 trail = max(faded, live);
		float keep = step(0.0001, p);
		trail *= keep;

		vec3 dark_trail = mix(vec3(1.0), hist, p);
		vec3 mid_trail = mix(vec3(0.5), hist, p);

		float lum = max(max(trail.r, trail.g), trail.b);
		float a = op;
		if (b >= 0.001) {
			a = op * smoothstep(0.035, 0.26, lum);
		}

		vec3 blended = trail;
		if (blend_mode == BLEND_BRIGHTEST) {
			blended = max(scene, trail);
		} else if (blend_mode == BLEND_EDGES) {
			blended = abs(scene - trail);
		} else if (blend_mode == BLEND_DARKEST) {
			blended = min(scene, dark_trail);
			a = op;
		} else if (blend_mode == BLEND_CONTRAST) {
			blended = overlay_blend(scene, mid_trail);
			a = op;
		} else if (b < 0.001) {
			blended = mix(hist, scene, max(1.0 - p, 0.0));
			a = op;
		}
		COLOR = vec4(blended, a);
	}
}
