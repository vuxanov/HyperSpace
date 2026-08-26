extends SceneTree

## Enable LFX and verify shaders bind (headless-safe). Optional image check when GPU available.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := change_scene_to_file("res://ui/main.tscn")
	if err != OK:
		push_error("LFX smoke: could not load main.tscn (%s)" % err)
		quit(2)
		return

	for i in 20:
		await process_frame

	var director := root.get_node_or_null("ShowDirector")
	if director == null:
		push_error("LFX smoke: ShowDirector missing")
		quit(2)
		return

	for eid in ["glitch", "chromatic", "hole"]:
		director.call("set_effect", str(eid), true, {
			"intensity": 1.2,
			"amount": 1.5,
			"rate": 2.0,
			"v_size": 24.0,
			"h_size": 48.0,
			"rgb_split": 0.9,
			"slice_chaos": 0.7,
			"threshold": 0.35,
			"stretch": 0.6,
			"drive_mode": "auto",
		})

	for i in 12:
		await process_frame

	var stack := root.find_child("EffectStack", true, false)
	if stack == null:
		push_error("LFX smoke: EffectStack missing")
		quit(2)
		return

	var ok_count := 0
	for child in stack.get_children():
		if child is CanvasLayer and child.visible:
			var mat_ok := false
			for sub in child.get_children():
				if sub is ColorRect and sub.material is ShaderMaterial:
					var sm := sub.material as ShaderMaterial
					if sm.shader != null:
						mat_ok = true
			if mat_ok:
				ok_count += 1

	print("LFX_SMOKE effects_with_shader=%d" % ok_count)
	if ok_count < 3:
		push_error("LFX smoke FAIL: expected 3 visible screen FX with shaders")
		quit(1)
		return

	var main := root.get_child(root.get_child_count() - 1)
	var vp: SubViewport = null
	if main:
		vp = main.get_node_or_null("Root/OutputPane/OutputColumn/OutputViewportContainer/OutputViewport") as SubViewport
	if vp:
		var tex := vp.get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var w := mini(img.get_width(), 96)
				var h := mini(img.get_height(), 96)
				var samples := 0
				var near_white := 0
				var sum_l := 0.0
				for y in range(0, h, 3):
					for x in range(0, w, 3):
						var c := img.get_pixel(x, y)
						var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
						sum_l += l
						samples += 1
						if c.r > 0.95 and c.g > 0.95 and c.b > 0.95:
							near_white += 1
				var white_ratio := float(near_white) / float(maxi(samples, 1))
				var avg_l := sum_l / float(maxi(samples, 1))
				print("LFX_SMOKE white_ratio=%.3f avg_l=%.3f" % [white_ratio, avg_l])
				if white_ratio > 0.92 and avg_l > 0.92:
					push_error("LFX smoke FAIL: preview is solid white")
					quit(1)
					return
			else:
				print("LFX_SMOKE note: get_image unavailable (dummy/headless renderer)")

	print("LFX_SMOKE OK")
	quit(0)
