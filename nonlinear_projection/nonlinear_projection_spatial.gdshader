shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Unique sampler names first so they occupy texture slots 0..n.
// Warp params are regular uniforms AFTER samplers (also stamped as instance
// params on GeometryInstance3D for injected shaders). Never `global uniform`.

uniform vec4 np_albedo_color : source_color = vec4(1.0);
uniform sampler2D np_albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float np_use_albedo_tex = 0.0;
uniform vec3 np_uv_scale = vec3(1.0, 1.0, 1.0);
uniform vec3 np_uv_offset = vec3(0.0, 0.0, 0.0);
uniform float np_use_triplanar = 0.0;
uniform float np_use_vertex_color = 0.0;

uniform float np_roughness : hint_range(0.0, 1.0) = 0.7;
uniform float np_metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D np_orm_tex : filter_linear_mipmap, repeat_enable;
uniform float np_use_orm_tex = 0.0;
uniform float np_orm_rough_ch = 1.0;
uniform float np_orm_metal_ch = 2.0;
uniform float np_orm_ao_ch = 0.0;
uniform float np_use_ao = 0.0;
uniform float np_ao_light_affect = 0.0;

uniform sampler2D np_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float np_use_normal_tex = 0.0;
uniform float np_normal_scale = 1.0;

uniform vec4 np_emission_color : source_color = vec4(0.0);
uniform sampler2D np_emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float np_use_emission_tex = 0.0;
uniform float np_emission_energy = 0.0;

uniform float np_alpha_blend = 0.0;

// Warp — regular uniforms, after every sampler.
uniform float np_u_enabled = 0.0;
uniform float np_u_distortion_strength = 1.0;
uniform float np_u_transition_start = 4.0;
uniform float np_u_transition_end = 35.0;
uniform float np_u_max_bend_angle = 1.5708;
uniform float np_u_easing_mode = 1.0;
uniform float np_u_vertical_scale = 1.0;
uniform float np_u_horizontal_scale = 1.0;
uniform float np_u_far_horizontal_scale = 1.0;
uniform float np_u_near_z_epsilon = 0.08;
uniform float np_u_debug = 0.0;
uniform vec3 np_u_camera_world_pos = vec3(0.0);
uniform float np_u_gameplay_only = 0.0;

#include "res://nonlinear_projection/nonlinear_projection.gdshaderinc"

varying float np_t;
varying vec3 v_world_pos;

float np_ch(vec4 t, float idx) {
	if (idx < 0.5) {
		return t.r;
	}
	if (idx < 1.5) {
		return t.g;
	}
	if (idx < 2.5) {
		return t.b;
	}
	if (idx < 3.5) {
		return t.a;
	}
	return dot(t.rgb, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	np_t = np_warp_vertex_and_normal(VERTEX, NORMAL, MODELVIEW_MATRIX, PROJECTION_MATRIX[3][3], CAMERA_POSITION_WORLD);
}

void fragment() {
	vec2 uv = UV * np_uv_scale.xy + np_uv_offset.xy;
	if (np_use_triplanar > 0.5) {
		uv = v_world_pos.xz * max(np_uv_scale.x, 0.001) + np_uv_offset.xy;
	}

	vec4 alb = np_albedo_color;
	if (np_use_albedo_tex > 0.5) {
		alb *= texture(np_albedo_tex, uv);
	}
	if (np_use_vertex_color > 0.5) {
		alb *= COLOR;
	}

	ALBEDO = alb.rgb;
	ROUGHNESS = np_roughness;
	METALLIC = np_metallic;
	SPECULAR = 0.5;

	if (np_use_orm_tex > 0.5) {
		vec4 orm = texture(np_orm_tex, uv);
		ROUGHNESS *= np_ch(orm, np_orm_rough_ch);
		METALLIC *= np_ch(orm, np_orm_metal_ch);
		if (np_use_ao > 0.5) {
			AO = np_ch(orm, np_orm_ao_ch);
			AO_LIGHT_AFFECT = np_ao_light_affect;
		}
	}

	if (np_use_normal_tex > 0.5) {
		NORMAL_MAP = texture(np_normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = np_normal_scale;
	}

	if (np_emission_energy > 0.001) {
		vec3 em = np_emission_color.rgb;
		if (np_use_emission_tex > 0.5) {
			em *= texture(np_emission_tex, uv).rgb;
		}
		EMISSION = em * np_emission_energy;
	}

	if (np_alpha_blend > 0.5) {
		ALPHA = alb.a;
	}

	np_apply_debug_albedo(ALBEDO, EMISSION, np_t);
}
