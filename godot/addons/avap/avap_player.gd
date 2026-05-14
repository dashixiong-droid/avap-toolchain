## AVAP 播放器
## 封装 Sprite2D，从 AVAPCache 获取帧数组，按帧率自动播放
##
## 用法:
##   var player = AVAPPlayer.new()
##   player.animation = "explosion"
##   add_child(player)
##   player.play()
@tool
extends Sprite2D
class_name AVAPPlayer


## 当前动画名称
@export var animation: String = "":
	set(v):
		if animation != v:
			animation = v
			_frames_loaded = false

## 是否循环播放
@export var loop: bool = true

## 播放速度倍率
@export var speed_scale: float = 1.0

## 自动播放
@export var autoplay: bool = false

## 居中显示
@export var centered: bool = true:
	set(v):
		centered = v
		if centered:
			offset = Vector2.ZERO
			_centered = true


var _frames: Array[Texture2D] = []
var _frame_index: int = 0
var _fps: float = 30.0
var _time_accum: float = 0.0
var _playing: bool = false
var _frames_loaded: bool = false
var _centered: bool = true


signal animation_finished()
signal frame_changed(index: int)


func _ready() -> void:
	if autoplay and animation != "":
		play()


func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return

	_time_accum += delta * speed_scale
	var frame_duration := 1.0 / _fps if _fps > 0 else 1.0 / 30.0

	while _time_accum >= frame_duration:
		_time_accum -= frame_duration
		_frame_index += 1

		if _frame_index >= _frames.size():
			if loop:
				_frame_index = 0
				animation_finished.emit()
			else:
				_frame_index = _frames.size() - 1
				_playing = false
				animation_finished.emit()
				return

		texture = _frames[_frame_index]
		frame_changed.emit(_frame_index)


## 播放动画（异步加载帧后开始播放）
func play() -> void:
	if animation == "":
		push_warning("AVAPPlayer: 未设置动画名称")
		return

	if not _frames_loaded:
		await _load_frames()

	_frame_index = 0
	_time_accum = 0.0
	_playing = true

	if not _frames.is_empty():
		texture = _frames[0]


## 停止播放
func stop() -> void:
	_playing = false


## 暂停
func pause() -> void:
	_playing = false


## 恢复
func resume() -> void:
	_playing = true


## 跳转到指定帧
func seek_frame(index: int) -> void:
	if _frames.is_empty():
		return
	_frame_index = clampi(index, 0, _frames.size() - 1)
	texture = _frames[_frame_index]


## 获取当前帧索引
func get_current_frame() -> int:
	return _frame_index


## 获取总帧数
func get_frame_count() -> int:
	return _frames.size()


## 获取动画时长（秒）
func get_duration() -> float:
	if _fps <= 0 or _frames.is_empty():
		return 0.0
	return float(_frames.size()) / _fps


## 是否正在播放
func is_playing() -> bool:
	return _playing


## 加载帧纹理
func _load_frames() -> void:
	var cache := _get_cache()
	if cache == null:
		push_error("AVAPPlayer: AVAPCache 未加载（请添加为 Autoload）")
		return

	_frames = await cache.get_frames(animation)

	# 获取帧率
	if cache._metadata != null:
		var anim := cache._metadata.find_animation(animation)
		if anim != null:
			_fps = anim.fps

	_frames_loaded = true

	# 设置纹理尺寸
	if not _frames.is_empty() and centered:
		offset = Vector2.ZERO


## 获取 AVAPCache 单例
func _get_cache() -> AVAPCache:
	# 尝试从 Autoload 获取
	var tree := get_tree()
	if tree and tree.root.has_node("AVAPCache"):
		return tree.root.get_node("AVAPCache") as AVAPCache
	# 尝试从场景查找
	if tree:
		var nodes := tree.get_nodes_in_group("avap_cache")
		if nodes.size() > 0:
			return nodes[0] as AVAPCache
	return null
