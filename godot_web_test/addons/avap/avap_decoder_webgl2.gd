## AVAP WebGL2 解码器
## 通过 JavaScriptBridge 调用浏览器端 <video> 解码 VP9。
extends Node

var _initialized: bool = false
var _ttl_ms: int = 30000

func _init() -> void:
	pass

func _is_webgl2() -> bool:
	return OS.has_feature("web")

func initialize(metadata_path: String) -> bool:
	if not _is_webgl2():
		push_error("AVAPWebGL2Decoder: 非 WebGL2 环境")
		return false

	if not _inject_js():
		push_error("AVAPWebGL2Decoder: JS 注入失败")
		return false

	var file := FileAccess.open(metadata_path, FileAccess.READ)
	if not file:
		push_error("AVAPWebGL2Decoder: 无法打开元数据: " + metadata_path)
		return false
	var metadata_json: String = file.get_as_text()
	file.close()

	var base_url: String = _res_to_url(metadata_path.get_base_dir())
	var js: String = "avap_init('%s', '%s', %d)" % [_escape_js(metadata_json), base_url, _ttl_ms]
	JavaScriptBridge.eval(js)

	_initialized = true
	print("AVAPWebGL2Decoder: 初始化完成")
	return true

func list_animations() -> PackedStringArray:
	if not _initialized:
		return PackedStringArray()
	var js: String = "JSON.stringify(avap_list())"
	var result = JavaScriptBridge.eval(js)
	if result == null or result == "":
		return PackedStringArray()
	var arr: Array = JSON.parse_string(result)
	var names := PackedStringArray()
	for name in arr:
		names.append(name)
	return names

func get_animation_info(anim_name: String) -> Dictionary:
	if not _initialized:
		return {}
	var js: String = "JSON.stringify(avap_info('%s'))" % [_escape_js(anim_name)]
	var result = JavaScriptBridge.eval(js)
	if result == null or result == "":
		return {}
	return JSON.parse_string(result)

func decode_animation(anim_name: String) -> Array:
	if not _initialized:
		push_error("AVAPWebGL2Decoder: 未初始化")
		return []

	var info: Dictionary = get_animation_info(anim_name)
	if info.is_empty():
		push_error("AVAPWebGL2Decoder: 动画不存在: " + anim_name)
		return []

	var w: int = info.get("width", 0)
	var h: int = info.get("height", 0)
	if w <= 0 or h <= 0:
		push_error("AVAPWebGL2Decoder: 无效尺寸")
		return []

	JavaScriptBridge.eval("avap_decode_start('%s')" % _escape_js(anim_name))

	while true:
		var done = JavaScriptBridge.eval("avap_decode_done()")
		if done == true:
			break
		var err = JavaScriptBridge.eval("avap_decode_error()")
		if err != null and err != "":
			push_error("AVAPWebGL2Decoder: " + str(err))
			return []
		await Engine.get_main_loop().process_frame

	var frame_count: int = JavaScriptBridge.eval("avap_decode_frame_count()")
	if frame_count <= 0:
		push_error("AVAPWebGL2Decoder: 解码结果为空")
		return []

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

	print("AVAPWebGL2Decoder: '%s' %d帧 %dx%d" % [anim_name, textures.size(), w, h])
	return textures

func release_all() -> void:
	if _initialized:
		JavaScriptBridge.eval("avap_release()")
		_initialized = false

func release_video(filename: String) -> void:
	if _initialized:
		JavaScriptBridge.eval("avap_release_video('%s')" % _escape_js(filename))

func set_ttl(ms: int) -> void:
	_ttl_ms = ms
	if _initialized:
		JavaScriptBridge.eval("avap_set_ttl(%d)" % ms)

func _inject_js() -> bool:
	var file := FileAccess.open("res://addons/avap/avap_decoder.js", FileAccess.READ)
	if not file:
		push_error("AVAPWebGL2Decoder: 无法读取 avap_decoder.js")
		return false
	var js_code: String = file.get_as_text()
	file.close()
	JavaScriptBridge.eval(js_code)
	return true

func _escape_js(s: String) -> String:
	return s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "")

func _res_to_url(res_path: String) -> String:
	return res_path.replace("res://", "")
