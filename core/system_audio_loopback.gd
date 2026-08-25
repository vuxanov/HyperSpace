class_name SystemAudioLoopback
extends Node

## WASAPI render-loopback helper → dedicated analysis bus (not the mic bus).
## Captures what Windows is playing so music can drive FFT. Hiss is not injected.
##
## NOT USED in the live path — the app analyses microphone input only. Kept for reference.

const PORT := 27123
const MAGIC0 := 0x48 ## 'H'
const MAGIC1 := 0x53 ## 'S'
const MAGIC2 := 0x4C ## 'L'
const MAGIC3 := 0x42 ## 'B'
const START_GRACE_SEC := 2.4
const PACKET_RESPAWN_SEC := 4.0
const SPAWN_RETRY_SEC := 12.0
## Hiss was ~6e-5. Alarm01 was 0.03–0.53. Quiet music sits between.
## Enter above hiss with margin; exit lower so it does not chatter.
const INJECT_ON := 0.00050
const INJECT_OFF := 0.00018

var render_device_name: String = ""
var last_error: String = ""
var stereo_mix_note: String = ""
var debug_peak: float = 0.0
var debug_rms: float = 0.0
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


func start_on_bus(bus_name: String) -> void:
	_bus_name = bus_name
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _running and _pid >= 0:
		_ensure_player()
		return
	stop()
	_failed = false
	_alive = false
	_start_age = 0.0
	_packet_age = 0.0
	last_error = ""
	_kill_stale_helper()
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
		last_error = "loopback helper missing or failed to start"
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
		last_error = "loopback helper missing or failed to start"
		_running = false
		_close_udp()
		_spawn_retry = SPAWN_RETRY_SEC
		return
	_failed = false
	last_error = ""


func _ensure_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		_player.name = "SystemAudioInject"
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
			var s := Vector2(float(pkt.decode_s16(o)) / 32768.0, float(pkt.decode_s16(o + 2)) / 32768.0)
			buf[i] = s
			var mag := maxf(absf(s.x), absf(s.y))
			peak = maxf(peak, mag)
			var m := (absf(s.x) + absf(s.y)) * 0.5
			acc += m * m
		var rms := sqrt(acc / float(frames))
		debug_peak = lerpf(debug_peak, peak, 0.45)
		debug_rms = lerpf(debug_rms, rms, 0.40)
		_alive = true
		_packet_age = 0.0
		last_error = ""
		# Always receive packets (including silence heartbeats). Only inject
		# music-sized energy so peak-normalize cannot paint hiss as a busy EQ.
		if _injecting:
			if peak < INJECT_OFF:
				_injecting = false
		else:
			if peak >= INJECT_ON:
				_injecting = true
		debug_injecting = _injecting
		if not _injecting:
			continue
		_pending.append_array(buf)


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
		# Push zeros so the 0.85s FFT window decays instead of holding hiss.
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
	var pid := OS.create_process(exe, PackedStringArray(["--port", str(PORT)]), false)
	return pid


func _exe_path() -> String:
	var local := ProjectSettings.globalize_path("res://tools/loopback/HyperSpaceLoopback.exe")
	if FileAccess.file_exists(local):
		return local
	var next_to_app := OS.get_executable_path().get_base_dir().path_join("HyperSpaceLoopback.exe")
	if FileAccess.file_exists(next_to_app):
		return next_to_app
	return ""


func _status_path() -> String:
	var temp := OS.get_environment("TEMP")
	if temp.is_empty():
		temp = OS.get_environment("TMP")
	return temp.path_join("hyperspace_loopback.status")


func _pid_path() -> String:
	var temp := OS.get_environment("TEMP")
	if temp.is_empty():
		temp = OS.get_environment("TMP")
	return temp.path_join("hyperspace_loopback.pid")


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
			var st := row.substr(6)
			if st == "error":
				_failed = true
		elif row.begins_with("message="):
			var msg := row.substr(8)
			if _failed:
				last_error = msg
		elif row.begins_with("device="):
			var dev := row.substr(7)
			if not dev.is_empty():
				render_device_name = dev
		elif row.begins_with("stereo_mix="):
			stereo_mix_note = row.substr(11)


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
