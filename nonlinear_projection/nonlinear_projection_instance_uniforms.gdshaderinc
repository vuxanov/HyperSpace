// Warp parameters as instance uniforms — separate UBO from material samplers.
// Forward+ clay-white was caused by packing these as regular uniforms ahead of
// albedo slots. Set from GeometryInstance3D.set_instance_shader_parameter.
// Default enabled=0 so injected shaders stay undistorted until the autoload stamps.

instance uniform float np_u_enabled = 0.0;
instance uniform float np_u_distortion_strength = 1.0;
instance uniform float np_u_transition_start = 4.0;
instance uniform float np_u_transition_end = 35.0;
instance uniform float np_u_max_bend_angle = 1.5708;
instance uniform float np_u_easing_mode = 1.0;
instance uniform float np_u_vertical_scale = 1.0;
instance uniform float np_u_horizontal_scale = 1.0;
instance uniform float np_u_far_horizontal_scale = 1.0;
instance uniform float np_u_near_z_epsilon = 0.08;
instance uniform float np_u_debug = 0.0;
instance uniform vec3 np_u_camera_world_pos = vec3(0.0);
instance uniform float np_u_gameplay_only = 0.0;
instance uniform float np_u_skip = 0.0;
