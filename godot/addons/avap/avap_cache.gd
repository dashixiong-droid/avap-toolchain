## AVAP 动画缓存
## 维护动画名 → 纹理数组的映射，支持 LRU 淘汰
##
## 用法:
##   AVAPCache.load_metadata("res://vfx/avap_metadata.json")
##   var frames = await AVAPCache.get_frames("explosion")
##   sprite.texture = frames[0]
class_name AVAPCache
extends Node


## 单例引用（Autoload）
static var _instance: AVAPCache = null

## 元数据
var _metadata: AVAPMetadata = null
var _base_dir: String = ""

## 纹理缓存: anim_name -> Array[Texture2D]
var _cache: Dictionary = {}

## LRU 访问时间: anim_name -> Time.get_ticks_msec()
var _access_time: Dictionary = {}

## 解码器
var _decoder: AVAPDecoder = null

## 最大缓存条目数（0 = 无限）
@export var max_cache_entries: int = 0

## 最大缓存显存估算 MB（0 = 无限）
@export var max_cache_mb: float = 0.0


func _ready() -> void:
	_instance = self
	_decoder = AVAPDecoder.new()
	_decoder.decode_completed.connect(_on_decode_completed)


## 加载元数据文件
func load_metadata(path: String) -> void:
	_metadata = AVAPMetadata.load_from_file(path)
	_base_dir = path.get_base_dir()
	print("AVAP: 加载元数据 %s (%d atlas, %d 动画)" % [
		path, _metadata.atlases.size(), _metadata.list_animations().size()
	])


## 同步获取动画帧（缓存命中直接返回，未命中返回空数组）
func get_frames_sync(anim_name: String) -> Array[Texture2D]:
	if _cache.has(anim_name):
		_access_time[anim_name] = Time.get_ticks_msec()
		return _cache[anim_name]
	return []


## 异步获取动画帧（缓存未命中时自动解码）
func get_frames(anim_name: String) -> Array[Texture2D]:
	# 缓存命中
	if _cache.has(anim_name):
		_access_time[anim_name] = Time.get_ticks_msec()
		return _cache[anim_name]

	# 缓存未命中，解码
	var frames := await _decode_and_cache(anim_name)
	return frames


## 预加载动画（在加载画面调用，解码但不阻塞）
func preload(anim_names: PackedStringArray) -> void:
	for name in anim_names:
		if not _cache.has(name):
			_decode_and_cache(name)


## 预加载所有动画
func preload_all() -> void:
	if _metadata == null:
		return
	preload(_metadata.list_animations())


## 释放指定动画的缓存
func release(anim_name: String) -> void:
	_cache.erase(anim_name)
	_access_time.erase(anim_name)


## 释放所有缓存
func release_all() -> void:
	_cache.clear()
	_access_time.clear()


## 列出已缓存的动画
func list_cached() -> PackedStringArray:
	var names: PackedStringArray = []
	for name in _cache:
		names.append(name)
	return names


## 列出所有可用动画
func list_available() -> PackedStringArray:
	if _metadata == null:
		return PackedStringArray()
	return _metadata.list_animations()


## 解码并缓存动画，返回纹理数组
func _decode_and_cache(anim_name: String) -> Array[Texture2D]:
	if _metadata == null:
		push_error("AVAP: 未加载元数据，请先调用 load_metadata()")
		return []

	var anim := _metadata.find_animation(anim_name)
	if anim == null:
		push_error("AVAP: 动画不存在: %s" % anim_name)
		return []

	var atlas := _metadata.get_atlas(anim.atlas_index)
	if atlas == null:
		push_error("AVAP: Atlas 不存在: #%d" % anim.atlas_index)
		return []

	# 在子线程解码
	var images: Array[Image] = await _decode_on_thread(anim, atlas)

	# 主线程创建纹理
	var textures: Array[Texture2D] = []
	for img in images:
		var tex := ImageTexture.create_from_image(img)
		textures.append(tex)

	# 缓存
	_cache[anim_name] = textures
	_access_time[anim_name] = Time.get_ticks_msec()

	# LRU 淘汰
	_evict_if_needed()

	print("AVAP: 解码完成 '%s' (%d帧, %dx%d)" % [
		anim_name, textures.size(), anim.rect_w, anim.rect_h
	])
	return textures


## 子线程解码
func _decode_on_thread(anim: AVAPMetadata.AVAPAnimation, atlas: AVAPMetadata.AVAPAtlas) -> Array[Image]:
	# 使用 Thread 在子线程执行解码
	var thread := Thread.new()
	var result: Array[Image] = []

	thread.start(func() -> void:
		result = _decoder.decode_animation(anim, atlas, _base_dir)
	)
	thread.wait_to_finish()

	return result


## LRU 淘汰
func _evict_if_needed() -> void:
	if max_cache_entries > 0 and _cache.size() > max_cache_entries:
		_evict_oldest(_cache.size() - max_cache_entries)


func _evict_oldest(count: int) -> void:
	# 按访问时间排序，淘汰最旧的
	var entries: Array = []
	for name in _access_time:
		entries.append({"name": name, "time": _access_time[name]})
	entries.sort_custom(func(a, b): return a["time"] < b["time"])

	for i in mini(count, entries.size()):
		var name: String = entries[i]["name"]
		_cache.erase(name)
		_access_time.erase(name)
		print("AVAP: LRU 淘汰 '%s'" % name)


func _on_decode_completed(anim_name: String, images: Array[Image]) -> void:
	# 异步解码完成回调（预留）
	pass
