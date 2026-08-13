extends RefCounted
class_name FlythroughPathBuilder

## Builds Curve3D paths for fly-throughs.

const STYLE_AUTO := "auto"
const STYLE_CIRCLE := "circle"
const STYLE_SQUARE := "square"
const STYLE_DIVE3D := "dive3d"

const STYLE_IDS: PackedStringArray = [
	STYLE_AUTO,
	STYLE_CIRCLE,
	STYLE_SQUARE,
	STYLE_DIVE3D,
]

const STYLE_LABELS: PackedStringArray = [
	"Auto (straight)",
	"Circle",
	"Square",
	"Dive 3D",
]


static func normalize_style(style: String) -> String:
	var s := style.strip_edges().to_lower()
	match s:
		"auto", "straight", "default", "":
			return STYLE_AUTO
		"circle", "loop", "orbit":
			return STYLE_CIRCLE
		"square", "box", "rect", "rectangle":
			return STYLE_SQUARE
		"dive3d", "dive", "3d", "multi", "multiplane", "roller":
			return STYLE_DIVE3D
		_:
			return STYLE_AUTO


static func style_label(style: String) -> String:
	var id := normalize_style(style)
	for i in STYLE_IDS.size():
		if STYLE_IDS[i] == id:
			return STYLE_LABELS[i]
	return STYLE_LABELS[0]


static func straight(length: float = 60.0, height: float = 0.0, points: int = 8) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	for i in points:
		var t := float(i) / float(maxi(points - 1, 1))
		curve.add_point(Vector3(0.0, height, -t * length))
	return curve


static func overland(length: float = 80.0, height: float = 8.0, points: int = 10) -> Curve3D:
	# Gentle path above a plane (same API as corridor — different height).
	return straight(length, height, points)


static func from_aabb(aabb: AABB, margin: float = 0.12, min_half_span: float = 12.0) -> Curve3D:
	## Straight path along the longest horizontal axis through the volume.
	## Elevates slightly above center so ground-heavy scans stay in frame.
	var size := aabb.size
	var center := aabb.get_center()
	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	var y := center.y + size.y * 0.08
	if size.x >= size.z:
		var half := maxf(size.x * (0.5 - margin), min_half_span)
		curve.add_point(Vector3(center.x - half, y, center.z))
		curve.add_point(Vector3(center.x + half, y, center.z))
	else:
		var half := maxf(size.z * (0.5 - margin), min_half_span)
		curve.add_point(Vector3(center.x, y, center.z + half))
		curve.add_point(Vector3(center.x, y, center.z - half))
	return curve


static func circle_from_aabb(aabb: AABB, margin: float = 0.18, min_radius: float = 10.0, points: int = 64) -> Curve3D:
	## Horizontal orbit around the environment center.
	var center := aabb.get_center()
	var size := aabb.size
	var horiz := maxf(size.x, size.z)
	var radius := maxf(horiz * (0.5 - margin), min_radius)
	var y := center.y + size.y * 0.1
	return circle(center, radius, y, points)


static func circle(center: Vector3, radius: float, y: float, points: int = 64) -> Curve3D:
	## Smooth closed orbit. Uses correct cubic-circle handles + Curve3D.closed
	## (no duplicated seam point — that caused tangent/orientation pops).
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	var n := maxi(points, 24)
	# Cubic Bezier circle: control distance = (4/3)*tan(θ/4)*r for arc θ=TAU/n.
	var tan_len := radius * (4.0 / 3.0) * tan(PI / float(2 * n))
	for i in n:
		var ang := float(i) / float(n) * TAU
		var pos := Vector3(
			center.x + cos(ang) * radius,
			y,
			center.z + sin(ang) * radius
		)
		var tangent := Vector3(-sin(ang), 0.0, cos(ang)) * tan_len
		curve.add_point(pos, -tangent, tangent)
	curve.closed = true
	return curve


static func square_from_aabb(aabb: AABB, margin: float = 0.18, min_half: float = 10.0, corner_soft: float = 0.52) -> Curve3D:
	## Closed horizontal rounded-square around the env center.
	var center := aabb.get_center()
	var size := aabb.size
	var half := maxf(maxf(size.x, size.z) * (0.5 - margin), min_half)
	var y := center.y + size.y * 0.1
	return square(center, half, y, corner_soft)


static func square(center: Vector3, half: float, y: float, corner_soft: float = 0.52) -> Curve3D:
	## Soft rounded rectangle: large corner radii + dense arc samples so travel
	## spends more path length in the turn (feels slower / less abrupt).
	var curve := Curve3D.new()
	curve.bake_interval = 0.15
	var soft := clampf(corner_soft, 0.28, 0.62)
	var radius := half * soft
	var straight := half - radius
	# Extra-dense corner samples → longer baked arc through each 90° turn.
	var arc_n := 28
	var pts: Array[Vector3] = []
	var tans: Array[Vector3] = []
	# Also sample short straight entry/exit pads so tangents ease into the arc.
	var pad_n := 3
	# Four corners: TR, BR, BL, TL in clockwise order on XZ (+Z forward start).
	# Start mid +Z edge so motion begins on a straight, then rounds each corner.
	var corners_c: Array[Vector3] = [
		Vector3(center.x + straight, y, center.z + straight), # +X+Z inner corner center
		Vector3(center.x + straight, y, center.z - straight), # +X-Z
		Vector3(center.x - straight, y, center.z - straight), # -X-Z
		Vector3(center.x - straight, y, center.z + straight), # -X+Z
	]
	# Arc start angles (from corner center): each covers -90° (clockwise).
	# Corner 0 (+X+Z): from +Z toward +X → angles PI/2 → 0
	var arc_start: PackedFloat32Array = PackedFloat32Array([PI * 0.5, 0.0, -PI * 0.5, PI])
	# Edge midpoints (start of each straight) for pad sampling.
	var edge_dirs: Array[Vector3] = [
		Vector3(1, 0, 0),  # after corner0, travel +X
		Vector3(0, 0, -1), # after corner1, travel -Z
		Vector3(-1, 0, 0), # after corner2, travel -X
		Vector3(0, 0, 1),  # after corner3, travel +Z
	]
	for c in 4:
		var cc: Vector3 = corners_c[c]
		var a0 := arc_start[c]
		# Straight pad into this corner so tangents ease into the arc.
		var prev_edge := (c + 3) % 4
		var into_dir: Vector3 = edge_dirs[prev_edge]
		var arc_entry := Vector3(cc.x + cos(a0) * radius, y, cc.z + sin(a0) * radius)
		for p in pad_n:
			var u := float(p) / float(pad_n)
			var back := (1.0 - u) * minf(radius * 0.45, straight * 0.35)
			var pad_pos := arc_entry - into_dir * back
			if pts.size() > 0 and pad_pos.distance_to(pts[pts.size() - 1]) < 0.02:
				continue
			pts.append(pad_pos)
			tans.append(into_dir)
		for k in arc_n + 1:
			var t := float(k) / float(arc_n)
			# Ease the parameter so more samples sit near mid-corner (smoother bake).
			var te := t * t * (3.0 - 2.0 * t)
			var ang := a0 - te * (PI * 0.5)
			var pos := Vector3(cc.x + cos(ang) * radius, y, cc.z + sin(ang) * radius)
			if pts.size() > 0 and pos.distance_to(pts[pts.size() - 1]) < 0.02:
				continue
			# Tangent follows clockwise travel (angle decreasing).
			var tangent_dir := Vector3(sin(ang), 0.0, -cos(ang))
			pts.append(pos)
			tans.append(tangent_dir)
	var count := pts.size()
	if count < 4:
		return curve
	# Handle length ~ chord spacing for smooth bake.
	for i in count:
		var prev: Vector3 = pts[(i - 1 + count) % count]
		var next: Vector3 = pts[(i + 1) % count]
		var spacing := prev.distance_to(next) * 0.32
		var tangent: Vector3 = tans[i] * spacing
		curve.add_point(pts[i], -tangent, tangent)
	curve.closed = true
	return curve


static func dive3d_from_aabb(aabb: AABB, margin: float = 0.16, min_half: float = 10.0) -> Curve3D:
	## Multi-plane closed flythrough: forward → dive down → go right → climb home.
	var center := aabb.get_center()
	var size := aabb.size
	var half := maxf(maxf(size.x, size.z) * (0.5 - margin), min_half)
	var y_mid := center.y + size.y * 0.12
	var y_low := center.y - maxf(size.y * 0.22, half * 0.18)
	var y_high := center.y + maxf(size.y * 0.28, half * 0.22)
	return dive3d(center, half, y_mid, y_low, y_high)


static func dive3d(center: Vector3, half: float, y_mid: float, y_low: float, y_high: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.3
	# Keyframes (world): cruise forward (−Z), dive, lateral (+X), climb, return (+Z/−X).
	var pts: Array[Vector3] = [
		Vector3(center.x, y_mid, center.z + half),                 # start
		Vector3(center.x, y_mid, center.z + half * 0.25),          # forward
		Vector3(center.x, y_mid, center.z - half * 0.55),          # still forward
		Vector3(center.x, lerpf(y_mid, y_low, 0.55), center.z - half), # begin dive
		Vector3(center.x, y_low, center.z - half),                 # bottom
		Vector3(center.x + half * 0.55, y_low, center.z - half),   # go right
		Vector3(center.x + half, y_low, center.z - half * 0.35),   # right + start climb
		Vector3(center.x + half, y_mid, center.z + half * 0.15),   # climb mid
		Vector3(center.x + half * 0.45, y_high, center.z + half * 0.75), # crest
		Vector3(center.x, y_mid, center.z + half),                 # close
	]
	for i in pts.size():
		var p: Vector3 = pts[i]
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var next: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var tangent := (next - prev) * 0.22
		curve.add_point(p, -tangent, tangent)
	return curve


static func build_styled(style: String, aabb: AABB, margin: float = 0.12, min_half: float = 12.0) -> Curve3D:
	## Build a non-auto path fitted to an environment AABB.
	match normalize_style(style):
		STYLE_CIRCLE:
			return circle_from_aabb(aabb, maxf(margin, 0.16), min_half)
		STYLE_SQUARE:
			return square_from_aabb(aabb, maxf(margin, 0.16), min_half)
		STYLE_DIVE3D:
			return dive3d_from_aabb(aabb, maxf(margin, 0.14), min_half)
		_:
			return from_aabb(aabb, margin, min_half)


static func fallback_aabb(half_span: float = 30.0, height: float = 8.0) -> AABB:
	return AABB(Vector3(-half_span, -height * 0.5, -half_span), Vector3(half_span * 2.0, height, half_span * 2.0))


static func baked_length(curve: Curve3D) -> float:
	if curve == null or curve.point_count < 2:
		return 0.0
	return curve.get_baked_length()
