class_name RawMicCapture
extends Node

## Raw microphone capture → dedicated analysis bus.
##
## Why this exists: the default recording endpoint on this machine is a Realtek mic array
## with the Lenovo AISPEECHAPO ("Voice Focus") in the chain. That APO is built for speech —
## it treats music as background noise and runs an AGC that lifts the room noise floor up to
## music level. Measured on this laptop, the processed stream's noise-floor peak is 0.120
## against a music peak of 0.142 (1.2x), so music and silence are indistinguishable. The
## same mic opened in WASAPI raw processing mode reads 0.021 against 0.103 (4.9x).
##
## Godot's AudioStreamMicrophone always gets the processed stream, so the raw signal comes
## from the native helper (tools/loopback/HyperSpaceLoopback.exe --mode mic) over UDP and is
## injected here through an AudioStreamGenerator.
##
## Raw mode also means no noise suppression, so the room's floor is always present in this
## stream. It is injected continuously anyway: AudioAnalyzer learns a per-band noise floor
## and subtracts it, which needs an uninterrupted signal to learn from. Gating here as well
## would only feed that estimator alternating zeros and bursts.

const PORT := 27124
const MAGIC0 := 0x48 ## 'H'
const MAGIC1 := 0x53 ## 'S'
const MAGIC2 := 0x4C ## 'L'
const MAGIC3 := 0x42 ## 'B'
const START_GRACE_SEC := 2.4
const PACKET_RESPAWN_SEC := 4.0
const SPAWN_RETRY_SEC := 12.0
## Floor tracking is reported for diagnostics only — it is what the room reads with nothing
## playing (measured ~0.021 peak here, against ~0.098 for music at moderate speaker volume).
const FLOOR_FALL := 0.30
const FLOOR_RISE := 0.010
## Raw mic sits far below a line-level signal. Lift it so FFT magnitudes land in the same
## range the analyser's absolute floors were tuned for. Clamped, so loud input just clips.
const MAKEUP_GAIN := 3.0

var mic_device_name: String = ""
var last_error: String = ""
var helper_mode: String = ""
var sysfx_note: String = ""
var debug_peak: float = 0.0
var debug_rms: float = 0.0
var debug_floor: float = 0.0
var debug_pushed: int = 0
var debug_avail: int = 0
var debug_injecting: bool = false

var _udp: PacketPeerUDP
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _pid: int = -1
var _running: bool = false
var _alive: bool = false
var _failed: bool = false
var _start_age: float = 0.0
var _packet_age: float = 0.0
var _status_age: float = 0.0
var _spawn_retry: float = 0.0
var _bus_name: String = ""
var _pending: PackedVector2Array = PackedVector2Array()
var _injecting: bool = false
var _floor_peak: float = 0.0


func is_alive() -> bool:
	return _alive


func is_running() -> bool:
	return _running


func is_failed() -> bool:
	return _failed


func current_peak() -> float:
	return debug_peak


func current_rms() -> float:
	return debug_rms


func is_injecting() -> bool:
	return _injecting


func is_raw_mode() -> bool:
	return helper_mode.begins_with("raw")


func describe_mode() -> String:
	if helper_mode.is_empty():
		return "starting"
	return helper_mode


func start_on_bus(bus_name: String) -> void:
	_bus_name = bus_name
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _running and _pid >= 0:
		_ensure_player()
		return
	# Before stop(), which clears the pid file: a helper left behind by a previous run of
	# the game would otherwise keep streaming into the same UDP port alongside the new one.
	_kill_stale_helper()
	stop()
	_failed = false
	_alive = false
	_start_age = 0.0
	_packet_age = 0.0
	last_error = ""
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(PORT)
	if err != OK:
		last_error = "UDP bind failed (%s)" % err
		_failed = true
		_udp = null
		_spawn_retry = SPAWN_RETRY_SEC
		set_process(true)
		return
	_ensure_player()
	_pid = _spawn_helper()
	if _pid < 0:
		last_error = "raw mic helper missing or failed to start"
		_failed = true
		_close_udp()
		_spawn_retry = SPAWN_RETRY_SEC
		set_process(true)
		return
	_running = true
	_failed = false
	set_process(true)


func stop() -> void:
	_running = false
	_alive = false
	_injecting = false
	debug_injecting = false
	set_process(false)
	_close_udp()
	if _player and is_instance_valid(_player) and _player.playing:
		_player.stop()
	_playback = null
	if _pid >= 0:
		OS.kill(_pid)
		_pid = -1
	_clear_pid_file()
	_pending = PackedVector2Array()


func flush_zeros() -> void:
	_pending = PackedVector2Array()
	_injecting = false
	debug_injecting = false
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var z := PackedVector2Array()
	z.resize(mini(n, 4096))
	_playback.push_buffer(z)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if _running or _pid >= 0:
			if _pid >= 0:
				OS.kill(_pid)
				_pid = -1
			_close_udp()
			_running = false


func _process(delta: float) -> void:
	if not _running:
		_spawn_retry = maxf(_spawn_retry - delta, 0.0)
		if _spawn_retry <= 0.0 and not _bus_name.is_empty():
			start_on_bus(_bus_name)
		return
	_start_age += delta
	_packet_age += delta
	_status_age += delta
	if _status_age >= 0.6:
		_status_age = 0.0
		_read_helper_status()
	_drain_udp()
	_push_generator()
	# Silence is not failure. Respawn only if packets stop (helper died).
	if _packet_age >= PACKET_RESPAWN_SEC and _start_age >= START_GRACE_SEC:
		_restart_helper()


func _restart_helper() -> void:
	if _pid >= 0:
		OS.kill(_pid)
		_pid = -1
	_kill_stale_helper()
	_pid = _spawn_helper()
	_start_age = 0.0
	_packet_age = 0.0
	_alive = false
	if _pid < 0:
		_failed = true
		last_error = "raw mic helper missing or failed to start"
		_running = false
		_close_udp()
		_spawn_retry = SPAWN_RETRY_SEC
		return
	_failed = false
	last_error = ""


func _ensure_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = "RawMicInject"
		add_child(_player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 48000.0
	gen.buffer_length = 0.25
	_player.stream = gen
	_player.bus = _bus_name
	_player.volume_db = 0.0
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	if "playback_type" in _player:
		_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	if not _player.playing:
		_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _drain_udp() -> void:
	if _udp == null:
		return
	var safety := 0
	while _udp.get_available_packet_count() > 0 and safety < 48:
		safety += 1
		var pkt: PackedByteArray = _udp.get_packet()
		if pkt.size() < 12:
			continue
		if pkt[0] != MAGIC0 or pkt[1] != MAGIC1 or pkt[2] != MAGIC2 or pkt[3] != MAGIC3:
			continue
		var frames := pkt.decode_u16(10)
		if frames <= 0 or pkt.size() < 12 + frames * 4:
			continue
		if _playback == null:
			_ensure_player()
		if _playback == null:
			continue
		var buf := PackedVector2Array()
		buf.resize(frames)
		var peak := 0.0
		var acc := 0.0
		for i in frames:
			var o := 12 + i * 4
			var l := clampf(float(pkt.decode_s16(o)) / 32768.0 * MAKEUP_GAIN, -1.0, 1.0)
			var r := clampf(float(pkt.decode_s16(o + 2)) / 32768.0 * MAKEUP_GAIN, -1.0, 1.0)
			var s := Vector2(l, r)
			buf[i] = s
			var mag := maxf(absf(l), absf(r))
			peak = maxf(peak, mag)
			var m := (absf(l) + absf(r)) * 0.5
			acc += m * m
		var rms := sqrt(acc / float(frames))
		debug_peak = lerpf(debug_peak, peak, 0.45)
		debug_rms = lerpf(debug_rms, rms, 0.40)
		_alive = true
		_packet_age = 0.0
		last_error = ""
		_track_floor(peak)
		_injecting = true
		debug_injecting = true
		_pending.append_array(buf)


func _track_floor(peak: float) -> void:
	if _floor_peak <= 0.0:
		_floor_peak = peak
	elif peak < _floor_peak:
		_floor_peak = lerpf(_floor_peak, peak, FLOOR_FALL)
	else:
		_floor_peak = lerpf(_floor_peak, peak, FLOOR_RISE)
	debug_floor = _floor_peak


func _push_generator() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.playing:
		_player.play()
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		return
	debug_avail = _playback.get_frames_available()
	if debug_avail <= 0:
		if _pending.size() > 48000:
			_pending = _pending.slice(_pending.size() - 24000)
		return
	if _pending.is_empty():
		# Push zeros so the FFT window decays instead of holding the last buffer.
		var z := PackedVector2Array()
		z.resize(mini(debug_avail, 2048))
		_playback.push_buffer(z)
		return
	var take := mini(_pending.size(), debug_avail)
	_playback.push_buffer(_pending.slice(0, take))
	debug_pushed += take
	if take >= _pending.size():
		_pending = PackedVector2Array()
	else:
		_pending = _pending.slice(take)


func _spawn_helper() -> int:
	var exe := _exe_path()
	if exe.is_empty():
		return -1
	var args := PackedStringArray(["--mode", "mic", "--port", str(PORT), "--raw", "1"])
	return OS.create_process(exe, args, false)


func _exe_path() -> String:
	var local := ProjectSettings.globalize_path("res://tools/loopback/HyperSpaceLoopback.exe")
	if FileAccess.file_exists(local):
		return local
	var next_to_app := OS.get_executable_path().get_base_dir().path_join("HyperSpaceLoopback.exe")
	if FileAccess.file_exists(next_to_app):
		return next_to_app
	return ""


func _temp_dir() -> String:
	var temp := OS.get_environment("TEMP")
	if temp.is_empty():
		temp = OS.get_environment("TMP")
	return temp


func _status_path() -> String:
	return _temp_dir().path_join("hyperspace_rawmic.status")


func _pid_path() -> String:
	return _temp_dir().path_join("hyperspace_rawmic.pid")


func _read_helper_status() -> void:
	var path := _status_path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n"):
		var row := String(line).strip_edges()
		if row.begins_with("state="):
			if row.substr(6) == "error":
				_failed = true
		elif row.begins_with("message="):
			if _failed:
				last_error = row.substr(8)
		elif row.begins_with("device="):
			var dev := row.substr(7)
			if not dev.is_empty():
				mic_device_name = dev
		elif row.begins_with("capture_mode="):
			var m := row.substr(13)
			if not m.is_empty():
				helper_mode = m
		elif row.begins_with("sysfx="):
			sysfx_note = row.substr(6)


func _kill_stale_helper() -> void:
	var path := _pid_path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var old := int(f.get_as_text().strip_edges())
	f.close()
	if old > 0:
		OS.kill(old)


func _clear_pid_file() -> void:
	var path := _pid_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _close_udp() -> void:
	if _udp:
		_udp.close()
		_udp = null
