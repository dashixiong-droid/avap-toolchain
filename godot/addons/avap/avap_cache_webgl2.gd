## AVAP 纹理缓存
## 解码后的 ImageTexture 数组缓存，LRU 淘汰策略。
## WebGL2 环境下使用 AVAPWebGL2Decoder。
class_name AVAPCache
extends Node

signal animation_loaded(anim_name: String)

# 最大缓存条目数（每个条目是一个动画的所有帧）
var max_entries: int = 20

var _cache: Dictionary = {}       # anim_name → Array[ImageTexture]
var _access_order: Array = []     # LRU 顺序
var _decoder: RefCounted = null   # AVAPWebGL2Decoder 或其他解码器
var _initialized: bool = false

func _ready() -> void:
	_init_decoder()

func _init_decoder() -> void:
	if OS.has_feature("web") and JavaScriptBridge.is_available():
		_decoder = AVAPWebGL2Decoder.new()
		print("[AVAPCache] 使用 WebGL2 解码器")
	else:
		# 桌面端回退：使用 ffmpeg 子进程解码器
		# TODO: 实现 AVAPFFmpegDecoder
		push_warning("[AVAPCache] 当前环境无可用解码器")
		return

## 初始化：加载元数据
func load_metadata(metadata_path: String) -> bool:
	if _decoder == null:
		push_error("[AVAPCache] 解码器未初始化")
		return false

	if _decoder is AVAPWebGL2Decoder:
		return _decoder.initialize(metadata_path)

	return false

## 获取动画帧（缓存命中直接返回，未命中则解码）
func get_animation(anim_name: String) -> Array:
	if _cache.has(anim_name):
		_touch(anim_name)
		return _cache[anim_name]

	# 解码
	var frames := _decode(anim_name)
	if frames.is_empty():
		return []

	# 缓存
	_put(anim_name, frames)
	animation_loaded.emit(anim_name)
	return frames

## 预加载动画（异步，不阻塞）
func preload(anim_name: String) -> void:
	if _cache.has(anim_name):
		return
	var frames := _decode(anim_name)
	if not frames.is_empty():
		_put(anim_name, frames)
		animation_loaded.emit(anim_name)

## 释放动画缓存
func release(anim_name: String) -> void:
	_cache.erase(anim_name)
	_access_order.erase(anim_name)

## 清空所有缓存
func clear() -> void:
	_cache.clear()
	_access_order.clear()

## 列出所有可用动画
func list_animations() -> PackedStringArray:
	if _decoder == null:
		return PackedStringArray()
	if _decoder is AVAPWebGL2Decoder:
		return _decoder.list_animations()
	return PackedStringArray()

# ── 内部 ──────────────────────────────────────────
func _decode(anim_name: String) -> Array:
	if _decoder == null:
		return []
	if _decoder is AVAPWebGL2Decoder:
		return await _decoder.decode_animation(anim_name)
	return []

func _touch(anim_name: String) -> void:
	_access_order.erase(anim_name)
	_access_order.append(anim_name)

func _put(anim_name: String, frames: Array) -> void:
	_cache[anim_name] = frames
	_touch(anim_name)

	# LRU 淘汰
	while _access_order.size() > max_entries:
		var oldest: String = _access_order.pop_front()
		_cache.erase(oldest)
