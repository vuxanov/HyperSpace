shader_type spatial;
// Display-referred media screen. Do NOT use `unshaded` here — that path ignores EMISSION
// and only outputs ALBEDO (which would force us back onto the white-default albedo path).
// Unbound sampler must be BLACK (hint_default_black), never Godot's default white.
render_mode fog_disabled, cull_disabled, depth_draw_opaque,
	ambient_light_disabled, shadows_disabled, specular_disabled;

uniform sampler2D tex_albedo : source_color, filter_linear, hint_default_black;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec4 modulate : source_color = vec4(1.0);
uniform float exposure_comp = 0.72;
uniform float has_tex = 0.0;
uniform float use_billboard = 0.0;
// Fallback tint when has_tex==0 (charcoal or error red).
uniform vec3 fallback_rgb = vec3(0.08, 0.08, 0.1);
// 0 Normal, 1 Multiply, 2 Overlay, 3 Screen, 4 Add, 5 Subtract, 6 Premultiplied.
uniform int blend_mode = 0;

// Vertex deform (tessellated PlaneMesh). Noise + cloth-like jiggle; top UV pinned.
uniform float deform_amount = 0.0;
uniform float deform_scale = 1.0;
uniform float deform_time = 0.0;
uniform vec3 deform_axes = vec3(1.0, 1.0, 1.0);
uniform float cloth_amount = 0.0;
uniform float cloth_stiffness = 0.55;
uniform float cloth_wind = 0.0;
uniform float cloth_time = 0.0;

#include "res://nonlinear_projection/nonlinear_projection_instance_uniforms.gdshaderinc"
#include "res://nonlinear_projection/nonlinear_projection.gdshaderinc"

varying float np_t;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	if (use_billboard > 0.5) {
		float sx = length(MODEL_MATRIX[0].xyz);
		float sy = length(MODEL_MATRIX[1].xyz);
		float sz = max(length(MODEL_MATRIX[2].xyz), 0.001);
		vec4 world_origin = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
		vec4 view_origin = VIEW_MATRIX * world_origin;
		MODELVIEW_MATRIX = mat4(
			vec4(sx, 0.0, 0.0, 0.0),
			vec4(0.0, sy, 0.0, 0.0),
			vec4(0.0, 0.0, sz, 0.0),
			view_origin
		);
	}
	float hang = clamp(1.0 - UV.y, 0.0, 1.0);
	hang = hang * hang;
	if (deform_amount > 0.0005) {
		float feature = max(deform_scale, 0.35);
		vec2 sp = UV * (6.0 / feature) + vec2(deform_time * 0.11, deform_time * 0.07);
		float n = vnoise2(sp) * 2.0 - 1.0;
		float n2 = vnoise2(sp + vec2(3.1, 8.7)) * 2.0 - 1.0;
		VERTEX += vec3(n * deform_axes.x, n2 * deform_axes.y, (n + n2) * 0.5 * deform_axes.z)
			* deform_amount * (0.35 + hang * 0.65);
	}
	if (cloth_amount > 0.0005) {
		// Grid UVs are continuous — low-frequency sheet waves, not per-texel jitter.
		float stiff = clamp(cloth_stiffness, 0.05, 1.0);
		float amp = cloth_amount * (1.0 - stiff * 0.72) * (0.12 + hang);
		float t = cloth_time;
		float ripple = sin(UV.x * 3.4 + t * (1.15 + cloth_wind * 1.6))
			* cos(UV.y * 2.2 + t * 0.85);
		float sway = sin(UV.y * 2.6 + t * 1.05) * cloth_wind;
		VERTEX.z += (ripple * 0.9 + sway * 0.25) * amp;
		VERTEX.x += sin(UV.y * 2.8 + t * 0.9) * amp * 0.18 * cloth_wind;
		VERTEX.y += cos(UV.x * 2.1 + t * 0.7) * amp * 0.08;
	}
	np_t = np_warp_vertex_frame(VERTEX, NORMAL, TANGENT, BINORMAL, MODELVIEW_MATRIX, PROJECTION_MATRIX[3][3], CAMERA_POSITION_WORLD);
}

vec3 hs_overlay(vec3 b, vec3 s) {
	return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(vec3(0.5), b));
}

vec3 hs_screen(vec3 b, vec3 s) {
	return vec3(1.0) - (vec3(1.0) - b) * (vec3(1.0) - s);
}

void fragment() {
	vec4 texel = vec4(fallback_rgb, 1.0);
	if (has_tex > 0.5) {
		texel = texture(tex_albedo, UV);
	}
	vec3 rgb = texel.rgb * modulate.rgb * exposure_comp;
	float src_a = clamp(texel.a * modulate.a, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	if (blend_mode <= 0) {
		EMISSION = rgb;
	} else {
		vec3 dst = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
		vec3 outc = rgb;
		if (blend_mode == 1) {
			outc = dst * rgb;
		} else if (blend_mode == 2) {
			outc = hs_overlay(dst, rgb);
		} else if (blend_mode == 3) {
			outc = hs_screen(dst, rgb);
		} else if (blend_mode == 4) {
			outc = dst + rgb;
		} else if (blend_mode == 5) {
			outc = dst - rgb;
		} else {
			// Premultiplied / alpha over (straight src * a).
			outc = rgb * src_a + dst * (1.0 - src_a);
		}
		EMISSION = outc;
		ALPHA = 1.0;
	}
	np_apply_debug_albedo(ALBEDO, EMISSION, np_t);
}
