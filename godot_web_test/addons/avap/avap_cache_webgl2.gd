## AVAP 纹理缓存（Autoload 单例）
## WebGL2 环境下使用浏览器端 <video> 解码。
extends Node

signal animation_loaded(anim_name: String)

var max_entries: int = 20

var _cache: Dictionary = {}
var _access_order: Array = []
var _decoder: Node = null
var _initialized: bool = false

func _ready() -> void:
	_init_decoder()

func _init_decoder() -> void:
	if OS.has_feature("web"):
		# WebGL2 环境：用 JS 解码器
		var d = Node.new()
		d.set_script(load("res://addons/avap/avap_decoder_webgl2.gd"))
		_decoder = d
		add_child(d)
		print("[AVAPCache] WebGL2 解码器")
	else:
		# Android / Desktop：用原生 VideoStreamPlayer 解码
		var d = Node.new()
		d.set_script(load("res://addons/avap/avap_decoder_native.gd"))
		_decoder = d
		add_child(d)
		print("[AVAPCache] 原生解码器 (%s)" % OS.get_name())

func load_metadata(metadata_path: String) -> bool:
	if _decoder == null:
		push_error("[AVAPCache] 解码器未初始化")
		return false
	var ok: bool = _decoder.initialize(metadata_path)
	if ok:
		_initialized = true
	return ok

func get_animation(anim_name: String) -> Array:
	if _cache.has(anim_name):
		_touch(anim_name)
		return _cache[anim_name]
	var frames: Array = await _decode(anim_name)
	if frames.is_empty():
		return []
	_put(anim_name, frames)
	animation_loaded.emit(anim_name)
	return frames

func release(anim_name: String) -> void:
	_cache.erase(anim_name)
	_access_order.erase(anim_name)

func clear() -> void:
	_cache.clear()
	_access_order.clear()

func list_animations() -> PackedStringArray:
	if _decoder == null:
		return PackedStringArray()
	return _decoder.list_animations()

func _decode(anim_name: String) -> Array:
	if _decoder == null:
		return []
	return await _decoder.decode_animation(anim_name)

func _touch(anim_name: String) -> void:
	_access_order.erase(anim_name)
	_access_order.append(anim_name)

func _put(anim_name: String, frames: Array) -> void:
	_cache[anim_name] = frames
	_touch(anim_name)
	while _access_order.size() > max_entries:
		var oldest: String = _access_order.pop_front()
		_cache.erase(oldest)
