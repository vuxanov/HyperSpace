shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Vertex noise deformation — feature size via noise_scale; amount in world units.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float use_albedo_tex = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float noise_amount = 0.0;
uniform float noise_scale = 1.0;
uniform float time_sec = 0.0;
uniform vec3 noise_seed = vec3(0.0);

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
	float a = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 4; i++) {
		a += (vnoise(p) * 2.0 - 1.0) * amp;
		p = p * 2.07 + vec3(1.7, 9.2, 2.3);
		amp *= 0.5;
	}
	return a;
}

void vertex() {
	float feature = max(noise_scale, 0.35);
	float freq = 1.0 / feature;
	vec3 sample_p = (VERTEX + noise_seed) * freq + vec3(time_sec * 0.09, time_sec * 0.06, time_sec * 0.07);
	// Independent axes so walls push in/out and sideways (classic noise displace).
	float nx = fbm(sample_p);
	float ny = fbm(sample_p + vec3(17.2, 3.1, 9.4));
	float nz = fbm(sample_p + vec3(4.8, 21.7, 2.6));
	vec3 axis_disp = vec3(nx, ny, nz);
	float along_n = fbm(sample_p + vec3(8.0, 1.0, 5.0));
	VERTEX += (NORMAL * along_n * 0.65 + axis_disp * 0.85) * noise_amount;
}

void fragment() {
	vec3 alb = albedo_color.rgb;
	if (use_albedo_tex > 0.5) {
		alb *= texture(albedo_tex, UV).rgb;
	}
	ALBEDO = alb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
