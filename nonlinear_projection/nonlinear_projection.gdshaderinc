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
	return np_u_enabled >= 0.5;
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

float np_warp_vertex_and_normal(inout vec3 vertex, inout vec3 normal, mat4 modelview, float proj33, vec3 view_origin) {
	// Ortho / directional-shadow: clip.w is independent of z, so [3][3] == 1.
	// proj33 must be passed from vertex() — helpers cannot read PROJECTION_MATRIX.
	// Return t instead of `out` — Godot 4.7 forbids passing a varying as out.
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
	vec3 n_view = mat3(modelview) * normal;
	float ny = n_view.y;
	float nz = n_view.z;
	n_view.y = ny * ca - nz * sa;
	n_view.z = ny * sa + nz * ca;
	normal = normalize(mat3(inv_mv) * n_view);
	return t_out;
}

void np_apply_debug_albedo(inout vec3 albedo, inout vec3 emission, float t_amt) {
	if (np_u_debug < 0.5) {
		return;
	}
	vec3 vis = mix(vec3(0.08, 0.22, 1.0), vec3(1.0, 0.12, 0.05), clamp(t_amt, 0.0, 1.0));
	albedo = vis;
	emission = vis * 0.4;
}
