shader_type canvas_item;

// 0 = rectilinear passthrough, then fisheye, circular/tunnel, equirectangular wrap.
// No early return in fragment (Godot 4.7 rejects it).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float lens_amount : hint_range(0.0, 1.0) = 0.0;
uniform float aspect : hint_range(0.2, 4.0) = 1.777;

vec3 sample_screen(vec2 uv) {
	return textureLod(screen_texture, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
}

vec3 sample_wrap(vec2 uv) {
	return textureLod(screen_texture, fract(uv), 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src = sample_screen(uv);
	float amt = clamp(lens_amount, 0.0, 1.0);
	float active = step(0.008, amt);

	vec2 c = uv - vec2(0.5);
	vec2 p = vec2(c.x * aspect, c.y);
	float r = length(p);
	float r_safe = max(r, 1e-5);
	vec2 dir = p / r_safe;

	// --- fisheye (0 .. 0.34) ---
	float t_fish = clamp(amt / 0.34, 0.0, 1.0);
	float theta_f = atan(r * (1.0 + t_fish * 5.5));
	float r_fish = theta_f / (1.55 + t_fish * 0.9);
	vec2 uv_fish = vec2(0.5) + vec2(dir.x / aspect, dir.y) * mix(r, r_fish, t_fish);

	// --- circular / tunnel (0.34 .. 0.68) ---
	float t_circ = clamp((amt - 0.34) / 0.34, 0.0, 1.0);
	float theta_c = r * mix(1.15, 3.05, t_circ);
	float r_circ = tan(clamp(theta_c * 0.5, 0.0, 1.45)) * mix(0.72, 0.28, t_circ);
	vec2 uv_circ = vec2(0.5) + vec2(dir.x / aspect, dir.y) * r_circ;
	float circle = length(c * vec2(aspect * 0.55, 1.0));
	float circ_mask = smoothstep(0.52, 0.46, circle);

	// --- equirectangular / spherical wrap (0.68 .. 1.0) ---
	float t_eq = clamp((amt - 0.68) / 0.32, 0.0, 1.0);
	float lon = c.x * 6.2831853 * mix(0.85, 1.0, t_eq);
	float lat = c.y * 3.14159265 * mix(0.55, 0.95, t_eq);
	vec3 sph = vec3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon));
	vec2 uv_eq = vec2(atan(sph.x, sph.z) / 6.2831853 + 0.5, asin(clamp(sph.y, -1.0, 1.0)) / 3.14159265 + 0.5);
	float eq_mask = mix(smoothstep(0.54, 0.47, circle), 1.0, t_eq);

	float in_fish = 1.0 - step(0.34, amt);
	float in_circ = step(0.34, amt) * (1.0 - step(0.68, amt));
	float in_eq = step(0.68, amt);

	vec2 sample_uv = uv_fish * in_fish + uv_circ * in_circ + uv_eq * in_eq;
	float mask = 1.0 * in_fish + circ_mask * in_circ + eq_mask * in_eq;
	vec3 mapped = sample_wrap(sample_uv) * in_eq + sample_screen(sample_uv) * (1.0 - in_eq);
	mapped *= mask;

	COLOR = vec4(mix(src, mapped, active), 1.0);
}
