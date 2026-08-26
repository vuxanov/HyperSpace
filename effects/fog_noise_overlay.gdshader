shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled,
	fog_disabled, shadows_disabled, ambient_light_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler3D noise_tex : filter_linear, repeat_enable;
uniform vec4 fog_color : source_color = vec4(0.76, 0.80, 0.84, 1.0);
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.5;
uniform float fog_begin = 5.0;
uniform float fog_end = 32.0;
uniform float noise_amt : hint_range(0.0, 1.0) = 0.5;
uniform float noise_scale : hint_range(0.0, 1.0) = 0.4;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float raw = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float dist = max(-view.z, 0.0);
	float span = max(fog_end - fog_begin, 0.5);
	float fog_f = clamp((dist - fog_begin) / span, 0.0, 1.0);

	float freq = mix(7.0, 1.15, clamp(noise_scale, 0.0, 1.0));
	float n = texture(noise_tex, vec3(SCREEN_UV * freq, 0.37)).r;
	float cut = mix(0.10, 0.52, clamp(noise_amt, 0.0, 1.0));
	float hole = smoothstep(cut - 0.02, cut + 0.05, n);

	ALBEDO = fog_color.rgb;
	ALPHA = fog_opacity * fog_f * hole;
}
