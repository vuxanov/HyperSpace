class_name AssetCache
extends RefCounted

## Shared path → resource cache with threaded loads for models / HDRIs / textures.
## Keeps previous frames live while new assets finish off the main thread.

const _SceneMeshFx := preload("res://core/scene_mesh_fx.gd")

enum Status { IDLE, LOADING, READY, FAILED }

static var _scenes: Dictionary = {}  # path_key -> PackedScene
static var _textures: Dictionary = {}  # path_key -> Texture2D
static var _inflight: Dictionary = {}  # path_key -> true
static var _failed: Dictionary = {}  # path_key -> true
static var _pending_cb: Dictionary = {}  # path_key -> Array[Callable]
static var _thread_jobs: Dictionary = {}  # path_key -> Dictionary
static var _ready_queue: Array = []
static var _queue_mutex := Mutex.new()
static var _poll_host: Node = null
static var _max_cache_scenes := 256
static var _max_cache_textures := 256


static func clear() -> void:
	_scenes.clear()
	_textures.clear()
	_inflight.clear()
	_failed.clear()
	_pending_cb.clear()
	_thread_jobs.clear()
	_queue_mutex.lock()
	_ready_queue.clear()
	_queue_mutex.unlock()


static func put_texture(path: String, tex: Texture2D) -> void:
	if tex == null:
		return
	_store_texture(normalize_key(path), tex)


static func put_scene(path: String, packed: PackedScene) -> void:
	if packed == null:
		return
	_store_scene(normalize_key(path), packed)


static func normalize_key(path: String) -> String:
	var n := path.replace("\\", "/").strip_edges()
	if n.begins_with("res://") or n.begins_with("user://"):
		return n
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if not project_root.ends_with("/"):
		project_root += "/"
	if n.begins_with(project_root):
		return "res://" + n.substr(project_root.length()).lstrip("/")
	# Windows paths may differ only by drive-letter case.
	if n.to_lower().begins_with(project_root.to_lower()):
		return "res://" + n.substr(project_root.length()).lstrip("/")
	return n


static func has_scene(path: String) -> bool:
	return _scenes.has(normalize_key(path))


static func has_texture(path: String) -> bool:
	return _textures.has(normalize_key(path))


static func get_scene(path: String) -> PackedScene:
	return _scenes.get(normalize_key(path), null) as PackedScene


static func get_texture(path: String) -> Texture2D:
	return _textures.get(normalize_key(path), null) as Texture2D


static func peek_or_load_scene_sync(path: String) -> PackedScene:
	## Prefer cache; sync-load only when an immediate result is required.
	var key := normalize_key(path)
	if _scenes.has(key):
		return _scenes[key] as PackedScene
	var packed := _try_load_packed_sync(key)
	if packed != null:
		_store_scene(key, packed)
	return packed


static func instantiate_scene(path: String, parent: Node) -> Node3D:
	var packed := get_scene(path)
	if packed == null:
		packed = peek_or_load_scene_sync(path)
	if packed == null or parent == null:
		return null
	var instance: Node = packed.instantiate()
	parent.add_child(instance)
	_SceneMeshFx.ensure_mesh_tangents(instance)
	if instance is Node3D:
		return instance as Node3D
	instance.queue_free()
	return null


static func request_scene(path: String, on_ready: Callable = Callable()) -> Status:
	var key := normalize_key(path)
	if key.is_empty():
		return Status.FAILED
	if _scenes.has(key):
		if on_ready.is_valid():
			on_ready.call(Status.READY, _scenes[key])
		return Status.READY
	if on_ready.is_valid():
		if not _pending_cb.has(key):
			_pending_cb[key] = []
		(_pending_cb[key] as Array).append(on_ready)
	if _inflight.has(key):
		_ensure_poll_host()
		return Status.LOADING
	_inflight[key] = true
	_failed.erase(key)
	_ensure_poll_host()
	if ResourceLoader.exists(key):
		var err := ResourceLoader.load_threaded_request(key, "", true)
		if err == OK:
			_thread_jobs[key] = {"kind": "resource", "path": key}
			return Status.LOADING
		# Imported scene exists — never fall through to raw GLTFDocument.
		var res: Resource = ResourceLoader.load(key)
		_inflight.erase(key)
		if res is PackedScene:
			_store_scene(key, res as PackedScene)
			_notify(key, Status.READY, res)
			return Status.READY
		_fail_key(key)
		return Status.FAILED
	var abs_path := _abs_path(key)
	var lower := abs_path.to_lower()
	if (lower.ends_with(".glb") or lower.ends_with(".gltf")) and FileAccess.file_exists(abs_path):
		_thread_jobs[key] = {"kind": "gltf", "path": key, "abs": abs_path}
		WorkerThreadPool.add_task(func() -> void: _worker_load_gltf(key, abs_path))
		return Status.LOADING
	_inflight.erase(key)
	_fail_key(key)
	return Status.FAILED


static func request_texture(path: String, on_ready: Callable = Callable()) -> Status:
	var key := normalize_key(path)
	if key.is_empty():
		return Status.FAILED
	if _textures.has(key):
		if on_ready.is_valid():
			on_ready.call(Status.READY, _textures[key])
		return Status.READY
	if on_ready.is_valid():
		if not _pending_cb.has(key):
			_pending_cb[key] = []
		(_pending_cb[key] as Array).append(on_ready)
	if _inflight.has(key):
		_ensure_poll_host()
		return Status.LOADING
	_inflight[key] = true
	_failed.erase(key)
	_ensure_poll_host()
	if ResourceLoader.exists(key):
		var err := ResourceLoader.load_threaded_request(key, "", true)
		if err == OK:
			_thread_jobs[key] = {"kind": "resource_tex", "path": key}
			return Status.LOADING
		# Imported texture exists — never re-parse .hdr via Image.load_from_file
		# (Godot's HDR loader warns on GAMMA/PRIMARIES/EXPOSURE headers).
		var res: Resource = ResourceLoader.load(key)
		_inflight.erase(key)
		if res is Texture2D:
			_store_texture(key, res as Texture2D)
			_notify(key, Status.READY, res)
			return Status.READY
		_fail_key(key)
		return Status.FAILED
	var abs_path := _abs_path(key)
	if FileAccess.file_exists(abs_path):
		_thread_jobs[key] = {"kind": "image", "path": key, "abs": abs_path}
		WorkerThreadPool.add_task(func() -> void: _worker_load_image(key, abs_path))
		return Status.LOADING
	_inflight.erase(key)
	_fail_key(key)
	return Status.FAILED


static func prefetch_paths(paths: Array) -> void:
	for p in paths:
		var s := str(p).strip_edges()
		if s.is_empty():
			continue
		var lower := s.to_lower()
		if lower.ends_with(".hdr") or lower.ends_with(".exr") \
				or lower.ends_with(".png") or lower.ends_with(".jpg") \
				or lower.ends_with(".jpeg") or lower.ends_with(".webp") \
				or lower.ends_with(".bmp") or lower.ends_with(".tga"):
			request_texture(s)
		elif lower.ends_with(".glb") or lower.ends_with(".gltf") \
				or lower.ends_with(".fbx") or lower.ends_with(".tscn"):
			request_scene(s)
		# GIF / video handled by MediaImport.warm_path (separate caches).


static func inflight_count() -> int:
	return _inflight.size()


static func is_inflight(path: String) -> bool:
	return _inflight.has(normalize_key(path))


static func has_failed(path: String) -> bool:
	return _failed.has(normalize_key(path))


static func threaded_progress(path: String) -> float:
	## 0–1 for an in-flight ResourceLoader job; 0 if unknown / worker-thread.
	var key := normalize_key(path)
	if key.is_empty():
		return 0.0
	if _scenes.has(key) or _textures.has(key) or _failed.has(key):
		return 1.0
	if not _thread_jobs.has(key):
		return 0.0
	var job: Dictionary = _thread_jobs[key]
	var kind := str(job.get("kind", ""))
	if kind != "resource" and kind != "resource_tex":
		return 0.0
	var progress: Array = []
	var st := ResourceLoader.load_threaded_get_status(str(job.get("path", key)), progress)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		return 1.0
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not progress.is_empty():
		return clampf(float(progress[0]), 0.0, 0.99)
	return 0.0


static func is_path_cached(path: String) -> bool:
	var key := normalize_key(path)
	if key.is_empty():
		return false
	var lower := key.to_lower()
	if lower.ends_with(".hdr") or lower.ends_with(".exr") \
			or lower.ends_with(".png") or lower.ends_with(".jpg") \
			or lower.ends_with(".jpeg") or lower.ends_with(".webp") \
			or lower.ends_with(".bmp") or lower.ends_with(".tga"):
		return _textures.has(key)
	if lower.ends_with(".glb") or lower.ends_with(".gltf") \
			or lower.ends_with(".fbx") or lower.ends_with(".tscn"):
		return _scenes.has(key)
	return false


static func warm_paths(paths: Array) -> int:
	## Kick threaded loads for every model/HDRI/still. Returns remaining inflight count.
	prefetch_paths(paths)
	_ensure_poll_host()
	return _inflight.size()


static func set_poll_host(node: Node) -> void:
	_poll_host = node


static func poll() -> void:
	_drain_ready_queue()
	var keys: Array = _thread_jobs.keys()
	for key in keys:
		var job: Dictionary = _thread_jobs[key]
		var kind := str(job.get("kind", ""))
		if kind != "resource" and kind != "resource_tex":
			continue
		var path := str(job.get("path", key))
		var progress: Array = []
		var st := ResourceLoader.load_threaded_get_status(path, progress)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_thread_jobs.erase(key)
		_inflight.erase(key)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			var res: Resource = ResourceLoader.load_threaded_get(path)
			if kind == "resource_tex":
				_finish_texture(key, res)
			else:
				_finish_scene_resource(key, res)
		else:
			_fail_key(key)


static func _abs_path(key: String) -> String:
	if key.begins_with("res://") or key.begins_with("user://"):
		return ProjectSettings.globalize_path(key).replace("\\", "/")
	return key.replace("\\", "/")


static func _push_ready(item: Dictionary) -> void:
	_queue_mutex.lock()
	_ready_queue.append(item)
	_queue_mutex.unlock()


static func _drain_ready_queue() -> void:
	_queue_mutex.lock()
	var batch: Array = _ready_queue.duplicate()
	_ready_queue.clear()
	_queue_mutex.unlock()
	for item in batch:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var key := str(d.get("key", ""))
		var kind := str(d.get("kind", ""))
		_inflight.erase(key)
		_thread_jobs.erase(key)
		if kind == "gltf_packed":
			var packed: PackedScene = d.get("packed") as PackedScene
			if packed != null:
				_store_scene(key, packed)
				_notify(key, Status.READY, packed)
			else:
				_fail_key(key)
		elif kind == "image_ok":
			var img: Image = d.get("image") as Image
			if img != null and not img.is_empty():
				var tex := ImageTexture.create_from_image(img)
				_store_texture(key, tex)
				_notify(key, Status.READY, tex)
			else:
				_fail_key(key)
		else:
			_fail_key(key)


static func _worker_load_gltf(key: String, abs_path: String) -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(abs_path, state)
	if err != OK:
		_push_ready({"key": key, "kind": "fail"})
		return
	var scene := gltf.generate_scene(state)
	if scene == null:
		_push_ready({"key": key, "kind": "fail"})
		return
	var packed := PackedScene.new()
	if packed.pack(scene) != OK:
		scene.free()
		_push_ready({"key": key, "kind": "fail"})
		return
	scene.free()
	_push_ready({"key": key, "kind": "gltf_packed", "packed": packed})


static func _worker_load_image(key: String, abs_path: String) -> void:
	var img: Image = Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		_push_ready({"key": key, "kind": "fail"})
		return
	_push_ready({"key": key, "kind": "image_ok", "image": img})


static func _try_load_packed_sync(key: String) -> PackedScene:
	if ResourceLoader.exists(key):
		var res: Resource = ResourceLoader.load(key)
		if res is PackedScene:
			return res as PackedScene
	var abs_path := _abs_path(key)
	var lower := abs_path.to_lower()
	if (lower.ends_with(".glb") or lower.ends_with(".gltf")) and FileAccess.file_exists(abs_path):
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		if gltf.append_from_file(abs_path, state) == OK:
			var scene := gltf.generate_scene(state)
			if scene != null:
				var packed := PackedScene.new()
				if packed.pack(scene) == OK:
					scene.free()
					return packed
				scene.free()
	return null


static func _finish_scene_resource(key: String, res: Resource) -> void:
	if res is PackedScene:
		_store_scene(key, res as PackedScene)
		_notify(key, Status.READY, res)
		return
	_fail_key(key)


static func _finish_texture(key: String, res: Resource) -> void:
	if res is Texture2D:
		_store_texture(key, res as Texture2D)
		_notify(key, Status.READY, res)
		return
	_fail_key(key)


static func _store_scene(key: String, packed: PackedScene) -> void:
	_scenes[key] = packed
	_trim_dict(_scenes, _max_cache_scenes)


static func _store_texture(key: String, tex: Texture2D) -> void:
	_textures[key] = tex
	_trim_dict(_textures, _max_cache_textures)


static func _trim_dict(d: Dictionary, max_n: int) -> void:
	if d.size() <= max_n:
		return
	var keys: Array = d.keys()
	var drop := d.size() - max_n
	for i in drop:
		d.erase(keys[i])


static func _fail_key(key: String) -> void:
	_inflight.erase(key)
	_thread_jobs.erase(key)
	_failed[key] = true
	_notify(key, Status.FAILED, null)


static func _notify(key: String, status: Status, payload: Variant) -> void:
	if not _pending_cb.has(key):
		return
	var cbs: Array = _pending_cb[key]
	_pending_cb.erase(key)
	for cb in cbs:
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(status, payload)


static func _ensure_poll_host() -> void:
	if _poll_host != null and is_instance_valid(_poll_host):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host := Node.new()
	host.name = "AssetCachePoll"
	host.set_script(load("res://core/asset_cache_poll.gd"))
	tree.root.call_deferred("add_child", host)
	_poll_host = host
