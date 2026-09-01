shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, specular_disabled,
	ambient_light_disabled, cull_disabled, depth_draw_opaque, skip_vertex_transform;

// One QuadMesh instance per source vertex (MultiMesh). UV is the real quad 0..1 —
// QuadMesh UV 0..1 + skip_vertex_transform billboard (Forward+ ignores POINT_SIZE).
// (POINT_SIZE is ignored). COLOR is MultiMesh instance color (baked vertex albedo).

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D tex_albedo : source_color, filter_linear, hint_default_white;
uniform float has_tex = 0.0;
uniform float point_size = 6.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform float exposure_comp = 1.0;
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

#include "res://nonlinear_projection/nonlinear_projection_instance_uniforms.gdshaderinc"
#include "res://nonlinear_projection/nonlinear_projection.gdshaderinc"

varying float np_t;
varying vec3 v_col;
varying vec2 v_corner;
varying vec2 v_src_uv;

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
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
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
	// Instance origin = source mesh vertex (MultiMesh translation). Quad VERTEX is
	// the billboard corner only — sampling vec3(0) made every point share one offset.
	vec3 vtx = vec3(0.0);
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	vec3 inst_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (noise_amount > 0.0005) {
		float feature = max(noise_scale, 0.35);
		float freq = 1.0 / feature;
		vec3 sample_p = (inst_world + noise_seed) * freq + vec3(time_sec * 0.14, time_sec * 0.09, time_sec * 0.11);
		float nx = fbm(sample_p);
		float ny = fbm(sample_p + vec3(17.2, 3.1, 9.4));
		float nz = fbm(sample_p + vec3(4.8, 21.7, 2.6));
		vec3 axis_disp = vec3(nx, ny, nz) * noise_axes;
		float along_n = fbm(sample_p + vec3(8.0, 1.0, 5.0));
		float axis_w = max(length(noise_axes), 0.001);
		// Keep point clouds in step with the mesh deformation response.
		vtx += (nrm * along_n * 0.7 * (axis_w / 1.732) + axis_disp * 0.95) * noise_amount * 0.12;
	}
	if (cloth_amount > 0.0005) {
		vec3 world = inst_world;
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
	np_t = np_warp_vertex_and_normal(vtx, nrm, MODELVIEW_MATRIX, PROJECTION_MATRIX[3][3], CAMERA_POSITION_WORLD);
	NORMAL = nrm;
	v_col = COLOR.rgb;
	v_src_uv = INSTANCE_CUSTOM.xy;
	// QuadMesh UV is 0..1 (not collapsed UV2). Billboard in view space; Forward+ ignores POINT_SIZE.
	vec2 corner = UV * 2.0 - 1.0;
	v_corner = corner;
	float px = max(point_size, 1.0);
	vec4 view = MODELVIEW_MATRIX * vec4(vtx, 1.0);
	vec2 vp = max(viewport_size, vec2(1.0));
	float z = max(abs(view.z), 0.02);
	float frustum_h = 2.0 * z / max(abs(PROJECTION_MATRIX[1][1]), 0.001);
	float half_px = max(px * 0.5 * frustum_h / vp.y, 0.001);
	view.xy += corner * half_px;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	if (dot(v_corner, v_corner) > 1.02) {
		discard;
	}
	vec3 rgb = albedo_color.rgb * v_col;
	if (has_tex > 0.5) {
		vec4 t = texture(tex_albedo, v_src_uv);
		if (t.a < 0.06) {
			discard;
		}
		rgb *= t.rgb;
	}
	rgb *= exposure_comp;
	ALBEDO = rgb;
	EMISSION = rgb;
	np_apply_debug_albedo(ALBEDO, EMISSION, np_t);
}
