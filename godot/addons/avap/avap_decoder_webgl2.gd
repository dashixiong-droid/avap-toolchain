## AVAP WebGL2 解码器
## 通过 JavaScriptBridge 调用浏览器端 <video> 解码 VP9，
## 提取 RGBA 帧数据，转为 Godot ImageTexture。
##
## <video> 缓存带 TTL：解码完成后默认 30s 自动释放底层解码缓冲区。
## 避免长时间持有 GPU 内存。下次解码同一视频时会重新加载。
##
## 仅在 WebGL2 导出下可用。
class_name AVAPWebGL2Decoder
extends RefCounted

var _initialized: bool = false
var _ttl_ms: int = 30000  ## 视频缓存 TTL（毫秒），默认 30s

func _init() -> void:
	if not _is_webgl2():
		push_warning("AVAPWebGL2Decoder: 非 WebGL2 环境，此解码器不可用")

## 检测是否在 WebGL2 环境
func _is_webgl2() -> bool:
	if not OS.has_feature("web"):
		return false
	return JavaScriptBridge.is_available()

## 初始化：注入 JS 解码器脚本 + 加载元数据
func initialize(metadata_path: String) -> bool:
	if not _is_webgl2():
		push_error("AVAPWebGL2Decoder: 非 WebGL2 环境")
		return false

	# 1. 注入 JS 解码器脚本
	if not _inject_js():
		push_error("AVAPWebGL2Decoder: JS 注入失败")
		return false

	# 2. 读取元数据
	var file := FileAccess.open(metadata_path, FileAccess.READ)
	if not file:
		push_error("AVAPWebGL2Decoder: 无法打开元数据: " + metadata_path)
		return false
	var metadata_json := file.get_as_text()
	file.close()

	# 3. 计算视频文件基路径
	var base_url := _res_to_url(metadata_path.get_base_dir())

	# 4. 调用 JS 初始化（传 TTL）
	var js := "avap_init('%s', '%s', %d)" % [_escape_js(metadata_json), base_url, _ttl_ms]
	JavaScriptBridge.eval(js)

	_initialized = true
	print("AVAPWebGL2Decoder: 初始化完成")
	return true

## 列出所有动画名
func list_animations() -> PackedStringArray:
	if not _initialized:
		return PackedStringArray()
	var js := "JSON.stringify(avap_list())"
	var result = JavaScriptBridge.eval(js)
	if result == null or result == "":
		return PackedStringArray()
	var arr: Array = JSON.parse_string(result)
	var names := PackedStringArray()
	for name in arr:
		names.append(name)
	return names

## 获取动画信息
func get_animation_info(anim_name: String) -> Dictionary:
	if not _initialized:
		return {}
	var js := "JSON.stringify(avap_info('%s'))" % [_escape_js(anim_name)]
	var result = JavaScriptBridge.eval(js)
	if result == null or result == "":
		return {}
	return JSON.parse_string(result)

## 解码动画：返回 ImageTexture 数组
## 使用轮询方案等待 JS 异步解码完成
func decode_animation(anim_name: String) -> Array:
	if not _initialized:
		push_error("AVAPWebGL2Decoder: 未初始化")
		return []

	# 获取动画尺寸
	var info := get_animation_info(anim_name)
	if info.is_empty():
		push_error("AVAPWebGL2Decoder: 动画不存在: " + anim_name)
		return []

	var w: int = info.get("width", 0)
	var h: int = info.get("height", 0)
	if w <= 0 or h <= 0:
		push_error("AVAPWebGL2Decoder: 无效尺寸: %dx%d" % [w, h])
		return []

	# 启动异步解码
	JavaScriptBridge.eval("avap_decode_start('%s')" % _escape_js(anim_name))

	# 轮询等待完成
	while true:
		var done = JavaScriptBridge.eval("avap_decode_done()")
		if done == true:
			break
		# 检查错误
		var err = JavaScriptBridge.eval("avap_decode_error()")
		if err != null and err != "":
			push_error("AVAPWebGL2Decoder: JS 解码错误: " + str(err))
			return []
		await Engine.get_main_loop().process_frame

	# 获取帧数
	var frame_count: int = JavaScriptBridge.eval("avap_decode_frame_count()")
	if frame_count <= 0:
		push_error("AVAPWebGL2Decoder: 解码结果为空")
		return []

	# 逐帧获取像素数据，转为 ImageTexture
	var textures: Array = []
	for i in range(frame_count):
		var raw = JavaScriptBridge.eval("avap_decode_get_frame(%d)" % i)
		if raw == null:
			continue
		var frame_array: Array = raw
		var data := PackedByteArray()
		data.resize(frame_array.size())
		for j in range(frame_array.size()):
			data[j] = int(frame_array[j])
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		textures.append(ImageTexture.create_from_image(img))

	print("AVAPWebGL2Decoder: 解码 '%s' %d帧 %dx%d" % [anim_name, textures.size(), w, h])
	return textures

## 释放所有 JS 侧资源（<video> + 离屏 canvas）
func release_all() -> void:
	if _initialized:
		JavaScriptBridge.eval("avap_release()")
		_initialized = false

## 释放指定视频的解码缓冲区
func release_video(filename: String) -> void:
	if _initialized:
		JavaScriptBridge.eval("avap_release_video('%s')" % _escape_js(filename))

## 设置视频缓存 TTL（毫秒）
## 解码完成后超过此时间自动释放 <video> 底层解码缓冲区
func set_ttl(ms: int) -> void:
	_ttl_ms = ms
	if _initialized:
		JavaScriptBridge.eval("avap_set_ttl(%d)" % ms)

# ── JS 注入 ──────────────────────────────────────
func _inject_js() -> bool:
	var file := FileAccess.open("res://addons/avap/avap_decoder.js", FileAccess.READ)
	if not file:
		push_error("AVAPWebGL2Decoder: 无法读取 avap_decoder.js")
		return false
	var js_code := file.get_as_text()
	file.close()
	JavaScriptBridge.eval(js_code)
	return true

# ── 工具 ──────────────────────────────────────────
func _escape_js(s: String) -> String:
	return s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "")

func _res_to_url(res_path: String) -> String:
	var url := res_path.replace("res://", "")
	return url
