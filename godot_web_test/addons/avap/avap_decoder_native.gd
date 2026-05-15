## AVAP 原生解码器（Android / iOS / Desktop）
## Android: 通过 GodotPlugin 桥接调用 MediaCodec 逐帧解码 VP9
## iOS: 通过 GDExtension 调用 AVAssetReader 逐帧解码 H.264
## Desktop: 占位（后续可用 GDExtension + FFmpeg）
extends Node

var _initialized: bool = false
var _metadata: Dictionary = {}
var _base_dir: String = ""
var _plugin: Object = null  # Android: JNISingleton, iOS: GDExtension
var _atlas_cache: Dictionary = {}
var _path_resolver: RefCounted = null  # AVAPPathResolver

func initialize(metadata_path: String) -> bool:
	var file := FileAccess.open(metadata_path, FileAccess.READ)
	if not file:
		push_error("AVAPNativeDecoder: 无法打开元数据: " + metadata_path)
		return false
	var metadata_json: String = file.get_as_text()
	file.close()
	
	var parsed = JSON.parse_string(metadata_json)
	if parsed == null or not parsed is Dictionary:
		push_error("AVAPNativeDecoder: 元数据解析失败")
		return false
	_metadata = parsed
	_base_dir = metadata_path.get_base_dir()
	
	# 初始化路径解析器
	_path_resolver = load("res://addons/avap/avap_path_resolver.gd").new()
	_path_resolver.base_dir = _base_dir
	
	if OS.has_feature("android"):
		_plugin = Engine.get_singleton("AVAPDecoder")
	elif OS.has_feature("ios"):
		# iOS: 加载 GDExtension 类
		if ClassDB.class_exists("AVAPDecoderIOS"):
			_plugin = ClassDB.instantiate("AVAPDecoderIOS")
	
	if _plugin != null:
		var has_vp9: bool = _plugin.hasVP9Support()
		var platform := "Android" if OS.has_feature("android") else "iOS"
		print("AVAPNativeDecoder: %s VP9 支持: %s" % [platform, str(has_vp9)])
		if not has_vp9:
			push_warning("AVAPNativeDecoder: 设备不支持 VP9 硬解")
	
	_initialized = true
	print("AVAPNativeDecoder: 初始化完成 (plugin=%s)" % str(_plugin != null))
	return true

## 设置自定义路径解析器（供外部 ResourceManager 接管）
func set_path_resolver(resolver: RefCounted) -> void:
	_path_resolver = resolver
	if _path_resolver and not _path_resolver.base_dir:
		_path_resolver.base_dir = _base_dir

## 设置自定义路径解析 callable
func set_custom_path_resolver(resolver_callable: Callable) -> void:
	if _path_resolver:
		_path_resolver.set_custom_resolver(resolver_callable)

func list_animations() -> PackedStringArray:
	if not _initialized:
		return PackedStringArray()
	var names := PackedStringArray()
	for atlas in _metadata.get("atlases", []):
		var anims = atlas.get("animations", {})
		for name in anims:
			names.append(name)
	return names

func get_animation_info(anim_name: String) -> Dictionary:
	if not _initialized:
		return {}
	for atlas in _metadata.get("atlases", []):
		var anims = atlas.get("animations", {})
		if anims.has(anim_name):
			return anims[anim_name]
	return {}

func decode_animation(anim_name: String) -> Array:
	if not _initialized:
		return []
	
	var info := get_animation_info(anim_name)
	if info.is_empty():
		push_error("AVAPNativeDecoder: 动画不存在: " + anim_name)
		return []
	
	var atlas_index: int = info.get("atlas_index", 0)
	var rect: Dictionary = info.get("rect", {})
	var rw: int = rect.get("w", 0)
	var rh: int = rect.get("h", 0)
	var frame_count: int = info.get("frame_count", 0)
	
	if rw <= 0 or rh <= 0 or frame_count <= 0:
		push_error("AVAPNativeDecoder: 无效动画参数")
		return []
	
	var atlas_data := _decode_atlas(atlas_index)
	if atlas_data.is_empty():
		return []
	
	var color_frames: Array = atlas_data["color_frames"]
	var alpha_frames: Array = atlas_data.get("alpha_frames", [])
	var rx: int = rect.get("x", 0)
	var ry: int = rect.get("y", 0)
	
	var textures: Array = []
	for i in range(mini(frame_count, color_frames.size())):
		var color_img: Image = color_frames[i]
		var alpha_img: Image = alpha_frames[i] if i < alpha_frames.size() else null
		
		var region := color_img.get_region(Rect2i(rx, ry, rw, rh))
		if alpha_img != null:
			var alpha_region := alpha_img.get_region(Rect2i(rx, ry, rw, rh))
			_apply_alpha(region, alpha_region)
		
		var tex := ImageTexture.create_from_image(region)
		textures.append(tex)
	
	print("AVAPNativeDecoder: '%s' 解码完成 %d帧 %dx%d" % [anim_name, textures.size(), rw, rh])
	return textures

func _decode_atlas(atlas_index: int) -> Dictionary:
	if _atlas_cache.has(atlas_index):
		return _atlas_cache[atlas_index]
	
	var atlas: Dictionary = _get_atlas(atlas_index)
	if atlas.is_empty():
		return {}
	
	var atlas_w: int = atlas.get("width", 0)
	var atlas_h: int = atlas.get("height", 0)
	
	# 根据平台选择视频文件：iOS 用 H.264 MP4，其他用 VP9 WebM
	var is_ios: bool = OS.has_feature("ios")
	var color_file: String = atlas.get("video_file_ios", atlas.get("video_file", "")) if is_ios else atlas.get("video_file", "")
	var alpha_file: String = atlas.get("alpha_video_file_ios", atlas.get("alpha_video_file", "")) if is_ios else atlas.get("alpha_video_file", "")
	
	if atlas_w <= 0 or atlas_h <= 0 or color_file == "":
		return {}
	
	var result: Dictionary = {"width": atlas_w, "height": atlas_h, "color_frames": [], "alpha_frames": []}
	
	if _plugin != null:
		# 通过路径解析器获取物理路径
		var color_path: String = _path_resolver.resolve(color_file)
		print("AVAPNativeDecoder: 解码颜色 %s → %s" % [color_file, color_path])
		var color_handle: int = _plugin.initDecoder(color_path)
		if color_handle < 0:
			push_error("AVAPNativeDecoder: 颜色解码器初始化失败")
			return {}
		
		var frame_idx := 0
		while true:
			var frame_bytes_raw = _plugin.getNextFrame(color_handle)
			if frame_bytes_raw == null:
				break
			var frame_bytes: PackedByteArray = frame_bytes_raw
			if frame_bytes.size() == 0:
				break
			var img := Image.create_from_data(atlas_w, atlas_h, false, Image.FORMAT_RGBA8, frame_bytes)
			result["color_frames"].append(img)
			frame_idx += 1
		_plugin.releaseDecoder(color_handle)
		print("AVAPNativeDecoder: 颜色 %d帧" % frame_idx)
		
		# 解码 alpha 轨道（逐帧）
		if alpha_file != "":
			var alpha_path: String = _path_resolver.resolve(alpha_file)
			print("AVAPNativeDecoder: 解码alpha %s → %s" % [alpha_file, alpha_path])
			var alpha_handle: int = _plugin.initDecoder(alpha_path)
			if alpha_handle >= 0:
				frame_idx = 0
				while true:
					var frame_bytes_raw = _plugin.getNextFrame(alpha_handle)
					if frame_bytes_raw == null:
						break
					var frame_bytes: PackedByteArray = frame_bytes_raw
					if frame_bytes.size() == 0:
						break
					var img := Image.create_from_data(atlas_w, atlas_h, false, Image.FORMAT_RGBA8, frame_bytes)
					result["alpha_frames"].append(img)
					frame_idx += 1
				_plugin.releaseDecoder(alpha_handle)
				print("AVAPNativeDecoder: alpha %d帧" % frame_idx)
	else:
		var total_frames: int = atlas.get("total_frames", 1)
		for i in range(total_frames):
			var img := Image.create(atlas_w, atlas_h, false, Image.FORMAT_RGBA8)
			img.fill(Color(1, 0.5, 0, 0.8))
			result["color_frames"].append(img)
	
	_atlas_cache[atlas_index] = result
	return result

func _apply_alpha(color_img: Image, alpha_img: Image) -> void:
	var w := color_img.get_width()
	var h := color_img.get_height()
	for y in range(h):
		for x in range(w):
			var c := color_img.get_pixel(x, y)
			var a := alpha_img.get_pixel(x, y)
			color_img.set_pixel(x, y, Color(c.r, c.g, c.b, a.r))

func _get_atlas(index: int) -> Dictionary:
	var atlases = _metadata.get("atlases", [])
	if index < atlases.size():
		return atlases[index]
	return {}

func release_all() -> void:
	_atlas_cache.clear()
	_initialized = false
