extends SceneTree

## Headless smoke: boot AudioAnalyzer briefly and print status / band sum.

func _initialize() -> void:
	await process_frame
	await process_frame
	var aa: Node = root.get_node_or_null("/root/AudioAnalyzer")
	if aa == null:
		push_error("AudioAnalyzer autoload missing")
		quit(1)
		return
	# Wall-clock wait so boot settle Timer (0.4s) + capture bind can finish.
	var elapsed := 0.0
	while elapsed < 1.6:
		await process_frame
		elapsed += 1.0 / 60.0
	var st: Variant = aa.call("get_state")
	print("AudioAnalyzer smoke status=", aa.call("get_capture_status"))
	print("AudioAnalyzer device=", aa.call("get_current_input_device"))
	print(
		"AudioAnalyzer input_level=", st.input_level,
		" energy=", st.energy,
		" bass=", st.bass
	)
	var spectrum_ok: bool = aa.get("_spectrum") != null
	var mic: Variant = aa.get("_mic_player")
	var playing: bool = mic != null and bool(mic.playing)
	print("AudioAnalyzer spectrum_bound=", spectrum_ok, " playing=", playing)
	quit(0)
