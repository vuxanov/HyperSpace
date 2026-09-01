shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Vertex noise deformation — feature size via noise_scale; amount in world units.
// noise_axes masks X/Y/Z displace independently (like Scale X/Y/Z).
// Samplers first; warp instance uniforms after so they cannot steal albedo slots.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_albedo_tex = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float noise_amount = 0.0;
uniform float noise_scale = 1.0;
uniform float time_sec = 0.0;
uniform vec3 noise_seed = vec3(0.0);
uniform vec3 noise_axes = vec3(1.0, 1.0, 1.0);
uniform float cloth_amount = 0.0;
uniform float cloth_stiffness = 0.55;
uniform float cloth_wind = 0.0;
uniform float cloth_time = 0.0;
uniform float cloth_gravity = 1.0;
uniform float use_vertex_color = 0.0;

#include "res://nonlinear_projection/nonlinear_projection_instance_uniforms.gdshaderinc"
#include "res://nonlinear_projection/nonlinear_projection.gdshaderinc"

varying float np_t;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float fbm(vec3 p) {
	// 2 octaves — was 4; vertex cost dominates on large envs / scatter.
	float a = 0.0;
	float amp = 0.65;
	for (int i = 0; i < 2; i++) {
		a += (vnoise(p) * 2.0 - 1.0) * amp;
		p = p * 2.07 + vec3(1.7, 9.2, 2.3);
		amp *= 0.5;
	}
	return a;
}

void vertex() {
	// Local copy so inout warp cannot restore rest-pose VERTEX and wipe noise.
	// np_u_skip disables warp only — noise/cloth still run.
	vec3 vtx = VERTEX;
	vec3 nrm = NORMAL;
	vec3 tgt = TANGENT;
	vec3 bnm = BINORMAL;
	if (noise_amount > 0.0005) {
		float feature = max(noise_scale, 0.35);
		float freq = 1.0 / feature;
		vec3 sample_p = (vtx + noise_seed) * freq + vec3(time_sec * 0.14, time_sec * 0.09, time_sec * 0.11);
		float nx = fbm(sample_p);
		float ny = fbm(sample_p + vec3(17.2, 3.1, 9.4));
		float nz = fbm(sample_p + vec3(4.8, 21.7, 2.6));
		vec3 axis_disp = vec3(nx, ny, nz) * noise_axes;
		float along_n = fbm(sample_p + vec3(8.0, 1.0, 5.0));
		float axis_w = max(length(noise_axes), 0.001);
		if (length(nrm) < 0.01) {
			nrm = vec3(0.0, 1.0, 0.0);
		}
		// The UI value remains open-ended, but its everyday range is intentionally gentle.
		vtx += (nrm * along_n * 0.7 * (axis_w / 1.732) + axis_disp * 0.95) * noise_amount * 0.12;
	}
	if (cloth_amount > 0.0005) {
		// Cloth is hang + wind + flutter — not fbm noise. Pin high local Y.
		vec3 world = (MODEL_MATRIX * vec4(vtx, 1.0)).xyz;
		float stiff = clamp(cloth_stiffness, 0.05, 1.0);
		float g = max(cloth_gravity, 0.0);
		float w = cloth_wind;
		float t = cloth_time;
		float pin = smoothstep(-0.6, 1.15, vtx.y);
		float hang = 1.0 - pin;
		float loose = (1.0 - stiff * 0.62) * cloth_amount;
		float sag = hang * g * (0.55 + hang * 0.45);
		float swing = sin(t * (0.65 + w * 0.55) + world.y * 0.12 + world.z * 0.08);
		float flutter = sin(t * 2.35 + world.x * 0.22) * w * 0.12 * hang;
		vec3 force = vec3(
			(swing * (0.55 + w * 0.9) + flutter) * hang,
			-sag + abs(swing) * w * 0.08 * hang,
			swing * (0.32 + w * 0.45) * hang
		);
		vtx += force * loose * (0.35 + hang);
	}
	np_t = np_warp_vertex_frame(vtx, nrm, tgt, bnm, MODELVIEW_MATRIX, PROJECTION_MATRIX[3][3], CAMERA_POSITION_WORLD);
	VERTEX = vtx;
	NORMAL = nrm;
	TANGENT = tgt;
	BINORMAL = bnm;
}

void fragment() {
	vec3 alb = albedo_color.rgb;
	if (use_albedo_tex > 0.5) {
		alb *= texture(albedo_tex, UV).rgb;
	}
	if (use_vertex_color > 0.5) {
		alb *= COLOR.rgb;
		ALBEDO = vec3(0.0);
		EMISSION = alb;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	} else {
		ALBEDO = alb;
		EMISSION = vec3(0.0);
		ROUGHNESS = roughness;
		METALLIC = metallic;
	}
	np_apply_debug_albedo(ALBEDO, EMISSION, np_t);
}
