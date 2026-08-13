shader_type canvas_item;

// Gray-Scott reaction-diffusion step. U in R, V in G.
// No early return in fragment (Godot 4.7).

uniform sampler2D prev_tex : filter_linear, repeat_enable;
uniform float feed : hint_range(0.01, 0.1) = 0.055;
uniform float kill : hint_range(0.04, 0.08) = 0.062;
uniform float speed : hint_range(0.1, 3.0) = 1.0;
uniform float seed_on : hint_range(0.0, 1.0) = 0.0;
uniform float time_sec = 0.0;

void fragment() {
	vec2 uv = UV;
	ivec2 sz = textureSize(prev_tex, 0);
	vec2 texel = vec2(1.0) / max(vec2(float(sz.x), float(sz.y)), vec2(1.0));
	vec2 prev = texture(prev_tex, uv).rg;
	float empty = step(dot(prev, prev), 0.000001);
	float n = fract(sin(dot(uv * 97.0 + vec2(time_sec * 0.13, time_sec * 0.07), vec2(12.9898, 78.233))) * 43758.5453);
	float blob = step(0.993, n) * seed_on;
	float u0 = mix(mix(prev.r, 1.0, empty), 1.0, seed_on * 0.08);
	float v0 = max(mix(prev.g, 0.0, empty), blob);

	vec2 p_r = texture(prev_tex, uv + vec2(texel.x, 0.0)).rg;
	vec2 p_l = texture(prev_tex, uv - vec2(texel.x, 0.0)).rg;
	vec2 p_u = texture(prev_tex, uv + vec2(0.0, texel.y)).rg;
	vec2 p_d = texture(prev_tex, uv - vec2(0.0, texel.y)).rg;
	vec2 lap = p_r + p_l + p_u + p_d - 4.0 * vec2(u0, v0);

	float f = clamp(feed, 0.01, 0.1);
	float k = clamp(kill, 0.04, 0.08);
	float uvv = u0 * v0 * v0;
	float du = 0.16 * lap.r - uvv + f * (1.0 - u0);
	float dv = 0.08 * lap.g + uvv - (k + f) * v0;
	float dt = 0.85 * clamp(speed, 0.1, 3.0);
	float u = clamp(u0 + du * dt, 0.0, 1.0);
	float v = clamp(v0 + dv * dt, 0.0, 1.0);
	COLOR = vec4(u, v, 0.0, 1.0);
}
