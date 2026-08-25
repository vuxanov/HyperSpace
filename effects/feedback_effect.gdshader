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
// 0 = crisp duplicated frame (LOD 0, no spread). BLUR_MAX_LOD * 0.35 == the old hardcoded 1.15.
uniform float blur : hint_range(0.0, 1.0) = 0.35;
// How the previous frame is composited onto the live one. 0 = Normal (the original look).
uniform int blend_mode : hint_range(0, 6) = 0;
uniform vec3 tint = vec3(1.02, 1.0, 1.08);

const float BLUR_MAX_LOD = 3.3;
const float BLUR_MAX_SPREAD = 0.006;

const int BLEND_NORMAL = 0;
const int BLEND_GLOW = 1;
const int BLEND_BRIGHTEST = 2;
const int BLEND_DARKEST = 3;
const int BLEND_SHADOW = 4;
const int BLEND_EDGES = 5;
const int BLEND_CONTRAST = 6;

vec3 overlay_blend(vec3 base, vec3 top) {
	vec3 lo = 2.0 * base * top;
	vec3 hi = vec3(1.0) - 2.0 * (vec3(1.0) - base) * (vec3(1.0) - top);
	return mix(lo, hi, step(vec3(0.5), base));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float z = zoom + audio_drive * 0.04;
	vec2 hist_uv = clamp((uv - 0.5) / z + 0.5, vec2(0.001), vec2(0.999));
	vec3 scene = textureLod(screen_texture, uv, 0.0).rgb;

	float b = clamp(blur, 0.0, 1.0);
	float lod = b * BLUR_MAX_LOD;
	float spread = b * BLUR_MAX_SPREAD;
	vec3 hist = textureLod(history_tex, hist_uv, lod).rgb;
	if (spread > 0.0) {
		vec3 ring = textureLod(history_tex, clamp(hist_uv + vec2(spread, 0.0), vec2(0.001), vec2(0.999)), lod).rgb;
		ring += textureLod(history_tex, clamp(hist_uv - vec2(spread, 0.0), vec2(0.001), vec2(0.999)), lod).rgb;
		ring += textureLod(history_tex, clamp(hist_uv + vec2(0.0, spread), vec2(0.001), vec2(0.999)), lod).rgb;
		ring += textureLod(history_tex, clamp(hist_uv - vec2(0.0, spread), vec2(0.001), vec2(0.999)), lod).rgb;
		hist = mix(hist, (hist + ring) * 0.2, b);
	}
	hist *= tint;

	float p = clamp(persistence, 0.0, 1.0);
	float op = clamp(max(opacity, mix_amount), 0.0, 1.0) * has_history;

	vec3 faded = hist * p;
	vec3 live = scene * (0.14 + 0.16 * p);
	vec3 trail = max(faded, live);
	float keep = step(0.0001, p);
	trail *= keep;

	// Each blend family needs its own identity element so Persistence 0 still means
	// "no trail", and so the frame-to-frame loop stays contractive: min/multiply against
	// a history that decays towards black would crush the whole frame to black in a few
	// frames. Additive modes fade to black, darkening modes fade to white, Contrast to grey.
	vec3 dark_trail = mix(vec3(1.0), hist, p);
	vec3 mid_trail = mix(vec3(0.5), hist, p);

	float lum = max(max(trail.r, trail.g), trail.b);
	float a = op * smoothstep(0.035, 0.26, lum);

	vec3 blended = trail;
	if (blend_mode == BLEND_GLOW) {
		blended = vec3(1.0) - (vec3(1.0) - scene) * (vec3(1.0) - trail);
	} else if (blend_mode == BLEND_BRIGHTEST) {
		blended = max(scene, trail);
	} else if (blend_mode == BLEND_EDGES) {
		blended = abs(scene - trail);
	} else if (blend_mode == BLEND_DARKEST) {
		blended = min(scene, dark_trail);
		a = op;
	} else if (blend_mode == BLEND_SHADOW) {
		blended = scene * dark_trail;
		a = op;
	} else if (blend_mode == BLEND_CONTRAST) {
		blended = overlay_blend(scene, mid_trail);
		a = op;
	}
	COLOR = vec4(blended, a);
}
