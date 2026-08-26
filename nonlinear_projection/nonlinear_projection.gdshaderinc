// Camera-space nonlinear projection. Functions only — parent shader must declare
// np_u_* first (regular uniforms AFTER samplers, or instance uniforms).
// warped = nonlinear_projection(camera_position)
// Distance source is camera-forward depth; swap np_source_distance() later for
// distance_along_road without coupling this include to any road system.
//
// Nested helpers cannot read PROJECTION_MATRIX / CAMERA_POSITION_WORLD in 4.7
// (Unknown identifier → wrap shader fails → clay-white fallback). Pass proj[3][3]
// from vertex() into np_warp_vertex_and_normal.

float np_ease(float t) {
	t = clamp(t, 0.0, 1.0);
	float mode = np_u_easing_mode;
	if (mode < 0.5) {
		return t;
	}
	if (mode < 1.5) {
		return t * t * (3.0 - 2.0 * t);
	}
	if (mode < 2.5) {
		return t * t;
	}
	if (mode < 3.5) {
		float u = 1.0 - t;
		return 1.0 - u * u;
	}
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float np_source_distance(vec3 cam_pos) {
	// Future: return distance_along_road instead of camera-forward depth.
	return max(-cam_pos.z, 0.0);
}

bool np_is_enabled() {
	return np_u_enabled >= 0.5 && np_u_skip < 0.5;
}

float np_warp_amount(vec3 cam_pos) {
	if (!np_is_enabled()) {
		return 0.0;
	}
	float dist = np_source_distance(cam_pos);
	float span = max(np_u_transition_end - np_u_transition_start, 1e-5);
	float t = clamp((dist - np_u_transition_start) / span, 0.0, 1.0);
	t = np_ease(t);
	t *= np_u_distortion_strength;
	return clamp(t, 0.0, 1.0);
}

vec3 nonlinear_projection(vec3 cam_pos) {
	if (!np_is_enabled()) {
		return cam_pos;
	}
	// Behind the camera: do not pull geometry through the near plane.
	if (cam_pos.z >= 0.0) {
		return cam_pos;
	}

	float t = np_warp_amount(cam_pos);
	if (t < 0.0001) {
		return cam_pos;
	}

	float angle = clamp(t * np_u_max_bend_angle, 0.0, 2.09439510239);
	float ca = cos(angle);
	float sa = sin(angle);

	// Pivot on the transition-start depth so near geometry stays put.
	float pivot_z = -max(np_u_transition_start, 0.0);
	vec3 rel = cam_pos;
	rel.z -= pivot_z;

	// Rotate around camera +X (pitch). Far -Z lifts toward +Y and depth collapses.
	float y0 = rel.y;
	float z0 = rel.z;
	rel.y = y0 * ca - z0 * sa;
	rel.z = y0 * sa + z0 * ca;
	rel.z += pivot_z;

	float hscale = mix(np_u_horizontal_scale, np_u_far_horizontal_scale, t);
	rel.x *= hscale;
	rel.y *= mix(1.0, np_u_vertical_scale, t);

	float z_eps = max(np_u_near_z_epsilon, 0.001);
	rel.z = min(rel.z, -z_eps);
	return rel;
}

void np_pitch_yz(inout vec3 v, float ca, float sa) {
	float y0 = v.y;
	float z0 = v.z;
	v.y = y0 * ca - z0 * sa;
	v.z = y0 * sa + z0 * ca;
}

float np_warp_vertex_frame(
	inout vec3 vertex,
	inout vec3 normal,
	inout vec3 tangent,
	inout vec3 binormal,
	mat4 modelview,
	float proj33,
	vec3 view_origin
) {
	// Ortho / directional-shadow: clip.w is independent of z, so [3][3] == 1.
	// proj33 must be passed from vertex() — helpers cannot read PROJECTION_MATRIX.
	if (!np_is_enabled() || abs(proj33) > 0.0001) {
		return 0.0;
	}
	if (np_u_gameplay_only > 0.5) {
		if (length(view_origin - np_u_camera_world_pos) > 8.0) {
			return 0.0;
		}
	}
	vec3 cam_pos = (modelview * vec4(vertex, 1.0)).xyz;
	float t_out = np_warp_amount(cam_pos);
	if (t_out < 0.0001) {
		return t_out;
	}
	vec3 warped = nonlinear_projection(cam_pos);
	mat4 inv_mv = inverse(modelview);
	vertex = (inv_mv * vec4(warped, 1.0)).xyz;

	float angle = clamp(t_out * np_u_max_bend_angle, 0.0, 2.09439510239);
	float ca = cos(angle);
	float sa = sin(angle);
	float hscale = mix(np_u_horizontal_scale, np_u_far_horizontal_scale, t_out);
	float vscale = mix(1.0, np_u_vertical_scale, t_out);
	mat3 mv = mat3(modelview);
	mat3 inv_m = mat3(inv_mv);

	// Same pitch as position. Non-uniform scale uses inverse-transpose on normals
	// and the forward scale on tangents so lighting/normal maps stay on the
	// correct hemisphere. Do not flip winding / NORMAL *= -1.
	vec3 n_view = mv * normal;
	np_pitch_yz(n_view, ca, sa);
	n_view.x /= max(hscale, 1e-5);
	n_view.y /= max(vscale, 1e-5);
	normal = normalize(inv_m * n_view);

	vec3 t_view = mv * tangent;
	np_pitch_yz(t_view, ca, sa);
	t_view.x *= hscale;
	t_view.y *= vscale;
	if (length(t_view) > 1e-8) {
		tangent = normalize(inv_m * t_view);
	}

	vec3 b_view = mv * binormal;
	np_pitch_yz(b_view, ca, sa);
	b_view.x *= hscale;
	b_view.y *= vscale;
	if (length(b_view) > 1e-8) {
		binormal = normalize(inv_m * b_view);
	}
	return t_out;
}

float np_warp_vertex_and_normal(inout vec3 vertex, inout vec3 normal, mat4 modelview, float proj33, vec3 view_origin) {
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	return np_warp_vertex_frame(vertex, normal, tangent, binormal, modelview, proj33, view_origin);
}

void np_apply_debug_albedo(inout vec3 albedo, inout vec3 emission, float t_amt) {
	if (np_u_debug < 0.5) {
		return;
	}
	vec3 vis = mix(vec3(0.08, 0.22, 1.0), vec3(1.0, 0.12, 0.05), clamp(t_amt, 0.0, 1.0));
	albedo = vis;
	emission = vis * 0.4;
}
