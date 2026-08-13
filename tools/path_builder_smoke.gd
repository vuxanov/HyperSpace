extends SceneTree

## Headless check: FlythroughPathBuilder styles produce usable closed curves.


func _initialize() -> void:
	var failed := 0
	var aabb := AABB(Vector3(-20, -4, -30), Vector3(40, 12, 60))
	var styles := [
		FlythroughPathBuilder.STYLE_AUTO,
		FlythroughPathBuilder.STYLE_CIRCLE,
		FlythroughPathBuilder.STYLE_SQUARE,
		FlythroughPathBuilder.STYLE_DIVE3D,
	]
	for style in styles:
		var curve: Curve3D = FlythroughPathBuilder.build_styled(str(style), aabb, 0.14, 10.0)
		if curve == null or curve.point_count < 2:
			push_error("path_builder_smoke: %s missing points" % style)
			failed += 1
			continue
		var length := curve.get_baked_length()
		if length < 1.0:
			push_error("path_builder_smoke: %s too short (%.3f)" % [style, length])
			failed += 1
			continue
		var y_span := 0.0
		var min_y := INF
		var max_y := -INF
		for i in curve.point_count:
			var y := curve.get_point_position(i).y
			min_y = minf(min_y, y)
			max_y = maxf(max_y, y)
		y_span = max_y - min_y
		print("OK %s points=%d length=%.1f y_span=%.2f closed=%s" % [
			style, curve.point_count, length, y_span, str(curve.closed)
		])
		if style == FlythroughPathBuilder.STYLE_DIVE3D and y_span < 1.0:
			push_error("path_builder_smoke: dive3d should vary in Y")
			failed += 1
		if style == FlythroughPathBuilder.STYLE_CIRCLE or style == FlythroughPathBuilder.STYLE_SQUARE:
			if not curve.closed:
				# Legacy duplicate-endpoint close still OK.
				var a := curve.get_point_position(0)
				var b := curve.get_point_position(curve.point_count - 1)
				if a.distance_to(b) > 0.05:
					push_error("path_builder_smoke: %s not closed (%.3f)" % [style, a.distance_to(b)])
					failed += 1
			# Continuity smoke: baked samples near seam should be close.
			var p0 := curve.sample_baked(0.0)
			var p1 := curve.sample_baked(maxf(length - 0.05, 0.0))
			if p0.distance_to(p1) > half_span_of(aabb) * 0.35:
				push_error("path_builder_smoke: %s seam jump (%.3f)" % [style, p0.distance_to(p1)])
				failed += 1
	if failed > 0:
		push_error("path_builder_smoke FAILED (%d)" % failed)
		quit(1)
	else:
		print("path_builder_smoke PASS")
		quit(0)


func half_span_of(aabb: AABB) -> float:
	return maxf(aabb.size.x, aabb.size.z) * 0.5
