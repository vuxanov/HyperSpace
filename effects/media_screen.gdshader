shader_type spatial;
// Display-referred media screen. Do NOT use `unshaded` here — that path ignores EMISSION
// and only outputs ALBEDO (which would force us back onto the white-default albedo path).
// Unbound sampler must be BLACK (hint_default_black), never Godot's default white.
render_mode fog_disabled, cull_disabled, depth_draw_opaque,
	ambient_light_disabled, shadows_disabled, specular_disabled;

uniform sampler2D tex_albedo : source_color, filter_linear, hint_default_black;
uniform vec4 modulate : source_color = vec4(1.0);
uniform float exposure_comp = 0.72;
uniform float has_tex = 0.0;
uniform float use_billboard = 0.0;
// Fallback tint when has_tex==0 (charcoal or error red).
uniform vec3 fallback_rgb = vec3(0.08, 0.08, 0.1);

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
}

void fragment() {
	vec3 rgb = fallback_rgb;
	if (has_tex > 0.5) {
		rgb = texture(tex_albedo, UV).rgb;
	}
	rgb *= modulate.rgb * exposure_comp;
	// Pure emission screen — no lit albedo (default white) contribution.
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = rgb;
}
