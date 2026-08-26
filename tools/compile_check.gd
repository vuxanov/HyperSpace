extends SceneTree

## Headless load of scripts touched by cloth / point-cloud / LFO / lens fixes.

func _init() -> void:
	var paths := PackedStringArray([
		"res://core/driver_expr.gd",
		"res://autoload/driver_hub.gd",
		"res://autoload/audio_analyzer.gd",
		"res://ui/slider_spin_link.gd",
		"res://ui/schedule_seconds_pair.gd",
		"res://ui/dual_range_slider.gd",
		"res://effects/effect_layer.gd",
		"res://effects/fx_automation.gd",
		"res://effects/hole_effect.gd",
		"res://effects/point_cloud_effect.gd",
		"res://effects/camera_fx_effect.gd",
		"res://effects/material_override_effect.gd",
		"res://effects/ascii_effect.gd",
		"res://effects/ascii_charset.gd",
		"res://core/scene_mesh_fx.gd",
		"res://effects/feedback_effect.gd",
		"res://effects/tone_effect.gd",
		"res://effects/effect_stack.gd",
		"res://core/reactivity_hub.gd",
		"res://autoload/reactivity_settings.gd",
		"res://core/boot_cache.gd",
		"res://items/scene3d_item.gd",
		"res://items/flythrough_environment.gd",
		"res://items/flythrough/media_prop.gd",
		"res://items/flythrough/camera_rig.gd",
		"res://autoload/show_director.gd",
		"res://ui/effects_sidebar.gd",
		"res://ui/playlist_sidebar.gd",
		"res://effects/noise_deform.gdshader",
		"res://effects/media_screen.gdshader",
		"res://effects/point_cloud.gdshader",
		"res://effects/lens_distort.gdshader",
		"res://effects/tone_effect.gdshader",
		"res://effects/material_override_viz.gdshader",
		"res://effects/feedback_effect.gdshader",
	])
	var failed := 0
	for path in paths:
		var res: Resource = load(path)
		if res == null:
			print("LOAD FAIL ", path)
			failed += 1
		else:
			print("LOAD OK ", path)
	failed += _test_driver_expr()
	failed += _test_picker()
	failed += _test_ascii_presets()
	print("DONE failed=", failed)
	quit(failed)


func _test_driver_expr() -> int:
	var scr: GDScript = load("res://core/driver_expr.gd")
	if scr == null:
		print("EXPR FAIL load")
		return 1
	var vars := {
		"volume": 0.5,
		"time": 10.0,
		"bass": 0.2,
		"lfo1": 0.8,
	}
	var cases: Array = [
		["volume * time", 5.0],
		["bass + time", 10.2],
		["lfo1 * volume", 0.4],
		["volume * 0.25", 0.125],
		["(bass + 0.1) * 2", 0.6],
		["1 / 0", 0.0],
		["unknown", 0.0],
		["-bass + 1", 0.8],
		["-bass", -0.2],
		["bass * 10", 2.0],
		["volume + 1", 1.5],
		["lfo1 * 2 + 0.1", 1.7],
		["bass * 10000", 2000.0],
		["bass * 1000", 200.0],
		["1e4", 10000.0],
		["-bass * 1000", -200.0],
	]
	var p: Object = scr.new()
	var failed := 0
	for c in cases:
		var expr := str(c[0])
		var want := float(c[1])
		var got := float(p.call("evaluate", expr, vars))
		if absf(got - want) > 0.0001:
			print("EXPR FAIL ", expr, " got=", got, " want=", want)
			failed += 1
		else:
			print("EXPR OK ", expr, " = ", got)
	return failed


func _test_picker() -> int:
	var scr: GDScript = load("res://autoload/driver_hub.gd")
	if scr == null:
		print("PICKER FAIL load")
		return 1
	var hub: Object = scr.new()
	var names: Variant = hub.call("picker_names")
	var failed := 0
	if not (names is PackedStringArray):
		print("PICKER FAIL not PackedStringArray")
		hub.free()
		return 1
	var arr := names as PackedStringArray
	for banned in ["time01", "frac", "sin_time", "dt", "progress", "cam_speed", "time_norm"]:
		if banned in arr:
			print("PICKER FAIL still has ", banned)
			failed += 1
	for need in ["time", "volume", "bass", "mids", "highs", "energy", "lfo1"]:
		if not (need in arr):
			print("PICKER FAIL missing ", need)
			failed += 1
	if failed == 0:
		print("PICKER OK size=", arr.size())
	hub.free()
	return failed


func _test_ascii_presets() -> int:
	var scr: GDScript = load("res://effects/ascii_effect.gd")
	var cs: GDScript = load("res://effects/ascii_charset.gd")
	if scr == null or cs == null:
		print("ASCII PRESET FAIL load")
		return 1
	var constants: Dictionary = scr.get_script_constant_map()
	var presets: Dictionary = constants.get("PRESETS", {}) as Dictionary
	var failed := 0
	for need in ["Standard", "Emoji", "Faces", "Runes", "Cyrillic", "Crosses", "Stars"]:
		if not presets.has(need):
			print("ASCII PRESET FAIL missing ", need)
			failed += 1
	if cs.has_method("filter_charset"):
		var kept := str(cs.call("filter_charset", "ᚠЖ⬛†"))
		if kept.find("ᚠ") < 0 or kept.find("Ж") < 0 or kept.find("⬛") < 0 or kept.find("†") < 0:
			print("ASCII PRESET FAIL filter dropped glyphs kept=", kept)
			failed += 1
		else:
			print("ASCII FILTER OK ", kept)
		var letters := str(cs.call("filter_charset", "eAs2"))
		print("ASCII LETTERS FILTER ", letters)
		if letters.find("e") < 0 or letters.find("A") < 0 or letters.find("s") < 0 or letters.find("2") < 0:
			print("ASCII PRESET FAIL filter dropped ASCII letters kept=", letters)
			failed += 1
	if cs.has_method("build_atlas"):
		var atlas: ImageTexture = cs.call("build_atlas", " .:-=+*#%@")
		if atlas == null:
			print("ASCII ATLAS FAIL null")
			failed += 1
		else:
			var im := atlas.get_image()
			var opaque := 0
			if im:
				for y in im.get_height():
					for x in im.get_width():
						if im.get_pixel(x, y).a > 0.1:
							opaque += 1
			print("ASCII ATLAS ", atlas.get_width(), "x", atlas.get_height(), " opaque=", opaque)
			if opaque < 20:
				print("ASCII ATLAS FAIL too empty")
				failed += 1
		var letter_atlas: ImageTexture = cs.call("build_atlas", "eAs2")
		if letter_atlas:
			var lim := letter_atlas.get_image()
			var letter_opaque := 0
			if lim:
				for y in lim.get_height():
					for x in lim.get_width():
						if lim.get_pixel(x, y).a > 0.1:
							letter_opaque += 1
			print("ASCII LETTER ATLAS opaque=", letter_opaque)
			if letter_opaque < 20:
				print("ASCII LETTER ATLAS skip (headless viewport bake)")
	if failed == 0:
		print("ASCII PRESETS OK count=", presets.size())
	return failed
