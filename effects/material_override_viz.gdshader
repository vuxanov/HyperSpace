shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled, shadows_disabled;

/// Tangent normal map as color, or world normals if the mesh has no map.
uniform sampler2D normal_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int has_normal_tex : hint_range(0, 1) = 0;

void fragment() {
	vec3 col;
	if (has_normal_tex == 1) {
		col = texture(normal_tex, UV).rgb;
	} else {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		col = wn * 0.5 + 0.5;
	}
	ALBEDO = col;
}
