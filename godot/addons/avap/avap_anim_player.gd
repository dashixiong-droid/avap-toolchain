## AVAP 动画控制器
## 独立的播放逻辑组件，不继承 Sprite2D。
## 任何节点都可以通过组合方式使用：
##   var player := AVAPAnimPlayer.new()
##   player.setup(cache, "explosion")
##   add_child(player)
##   player.play()
##
## 也可以直接调接口拿帧，自己控制渲染：
##   var frames := await AVAPCache.get_animation("explosion")
##   sprite.texture = frames[0]
class_name AVAPAnimPlayer
extends Node

## 播放完成（非循环时）
signal animation_finished()
## 帧切换，外部可用来驱动自己的渲染
signal frame_changed(frame_index: int)

@export var animation_name: String = ""
@export var loop: bool = true
@export var speed_scale: float = 1.0
@export var autoplay: bool = false

var _frames: Array = []       # Array[ImageTexture]
var _frame_index: int = 0
var _fps: float = 30.0
var _playing: bool = false
var _elapsed: float = 0.0
var _cache: AVAPCache = null

func _ready() -> void:
	if autoplay and animation_name != "":
		play(animation_name)

func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return

	_elapsed += delta
	var frame_duration := 1.0 / (_fps * speed_scale)

	while _elapsed >= frame_duration:
		_elapsed -= frame_duration
		_frame_index += 1

		if _frame_index >= _frames.size():
			if loop:
				_frame_index = 0
			else:
				_frame_index = _frames.size() - 1
				_playing = false
				animation_finished.emit()
				return

	frame_changed.emit(_frame_index)

## 获取当前帧纹理（外部渲染用）
func get_current_texture() -> Texture2D:
	if _frames.is_empty() or _frame_index >= _frames.size():
		return null
	return _frames[_frame_index]

## 设置动画源（手动绑定 cache，不依赖 Autoload）
func setup(cache: AVAPCache, anim_name: String) -> void:
	_cache = cache
	animation_name = anim_name

## 播放动画
func play(anim_name: String = "") -> void:
	if anim_name != "":
		animation_name = anim_name
	if animation_name == "":
		return

	if _cache == null:
		_cache = _find_cache()
	if _cache == null:
		push_error("AVAPAnimPlayer: AVAPCache 未找到")
		return

	_frames = await _cache.get_animation(animation_name)
	if _frames.is_empty():
		push_error("AVAPAnimPlayer: 解码失败: " + animation_name)
		return

	var info := {}
	if _cache._decoder:
		info = _cache._decoder.get_animation_info(animation_name)
	_fps = info.get("fps", 30.0)

	_frame_index = 0
	_elapsed = 0.0
	_playing = true
	frame_changed.emit(0)

func stop() -> void:
	_playing = false
	_frame_index = 0

func pause() -> void:
	_playing = false

func resume() -> void:
	if _frames.size() > 0:
		_playing = true

func get_current_frame() -> int:
	return _frame_index

func get_frame_count() -> int:
	return _frames.size()

func is_playing() -> bool:
	return _playing

func _find_cache() -> AVAPCache:
	var node := get_node_or_null("/root/AVAPCache")
	if node and node is AVAPCache:
		return node
	return null
