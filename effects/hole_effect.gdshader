shader_type canvas_item;

// Stretch-and-fall-in (not a swirl). Phase 0 = almost identity, 1 = fully sucked.
// Breathe: collapse → short peak/void → emerge. No early `return` (Godot 4.7).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float strength : hint_range(0.0, 2.0) = 0.75;
uniform float hole_size : hint_range(0.04, 0.85) = 0.20;
uniform float twist : hint_range(0.0, 8.0) = 0.00;
uniform float softness : hint_range(0.02, 0.8) = 0.30;
uniform float flow : hint_range(0.0, 2.0) = 0.50;
uniform float center_x : hint_range(0.0, 1.0) = 0.5;
uniform float center_y : hint_range(0.0, 1.0) = 0.5;
uniform float shape : hint_range(0.0, 1.0) = 0.0;
uniform float time_sec = 0.0;

vec3 sample_screen(vec2 uv) {
	return textureLod(screen_texture, clamp(uv, vec2(0.002), vec2(0.998)), 0.0).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src = sample_screen(uv);
	float active = smoothstep(0.0, 0.035, strength);

	float ar = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 1e-6);
	vec2 hole = vec2(center_x, center_y);
	vec2 raw = uv - hole;
	vec2 d_circ = raw * vec2(ar, 1.0);
	vec2 d = mix(d_circ, raw, shape);

	// Circular: Euclidean. Rectangle: high p-norm squircle so sides fall into a box aperture.
	float p = mix(2.0, 12.0, shape);
	vec2 ad = abs(d) + vec2(1e-5);
	float r = pow(pow(ad.x, p) + pow(ad.y, p), 1.0 / p);
	vec2 grad = vec2(
		pow(ad.x, p - 1.0) * sign(d.x),
		pow(ad.y, p - 1.0) * sign(d.y)
	);
	vec2 dir = grad / max(length(grad), 1e-5);

	float size = max(hole_size, 0.04);
	float soft = max(softness, 0.02);
	float nd = r / size;

	// Cycle: ~4–8s breathe. Flow = speed. 0..0.46 collapse, hold, 0.54..1 emerge.
	float hz = 0.12 + flow * 0.20;
	float u = fract(time_sec * hz);
	float collapse = 1.0 - pow(1.0 - smoothstep(0.0, 0.46, u), 1.55);
	float emerge = 1.0 - smoothstep(0.54, 1.0, u);
	float phase = min(collapse, emerge);

	float depth = min(strength * phase, 1.15);

	// Near-hole stretch starts immediately (1/r). Far pixels join soon so the
	// frame sides begin sliding, then the rest of the frame follows.
	float onset = clamp(smoothstep(0.50, 2.6, nd) * 0.20, 0.0, 0.28);
	float local_p = smoothstep(onset, min(onset + 0.34 + soft * 0.40, 1.0), phase);

	float inv_r = 1.0 / max(nd, 0.10);
	float g = local_p * mix(0.70, inv_r, 0.72);

	float k = depth * 0.80;
	float denom = max(1.0 - k * (g / (g + 1.05)), 0.22);
	float r_src = r / denom;

	// Edges of the frame start falling early; bulk pull grows toward peak.
	float edge = smoothstep(0.32, 1.85, nd);
	float edge_amt = smoothstep(0.05, 0.62, phase);
	r_src += size * strength * edge_amt * edge * (0.34 + soft * 0.38);
	r_src += r * depth * pow(phase, 1.35) * 0.20;

	// Twist is optional garnish. Default 0 = pure stretch/fall.
	float ang = twist * 0.18 * local_p * (1.0 / max(nd, 0.22));
	float ca = cos(ang);
	float sa = sin(ang);
	vec2 pulled = vec2(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);
	vec2 d_src = pulled * r_src;
	vec2 sample_d = mix(d_src / vec2(max(ar, 1e-5), 1.0), d_src, shape);
	vec2 sample_uv = hole + sample_d;

	vec3 warped = sample_screen(sample_uv);

	// Small void at peak only — scene stays readable.
	float void_r = size * mix(0.03, 0.26, pow(phase, 1.7) * smoothstep(0.18, 0.70, strength));
	float void_m = 1.0 - smoothstep(void_r * 0.12, void_r * (0.88 + soft * 0.5), r);
	void_m *= smoothstep(0.35, 0.78, phase) * 0.82;
	warped *= (1.0 - void_m);

	COLOR = vec4(mix(src, warped, active), 1.0);
}
