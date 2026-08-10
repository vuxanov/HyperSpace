extends RefCounted
class_name FlythroughPathBuilder

## Builds Curve3D paths for fly-throughs.


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


static func baked_length(curve: Curve3D) -> float:
	if curve == null or curve.point_count < 2:
		return 0.0
	return curve.get_baked_length()
