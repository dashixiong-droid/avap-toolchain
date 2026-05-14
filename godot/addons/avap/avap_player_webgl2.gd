## AVAP 播放器节点
## 继承 Sprite2D，从 AVAPCache 获取帧纹理并按帧率播放。
## 用法：添加到场景，调用 play("animation_name") 即可。
@tool
extends Sprite2D
class_name AVAPPlayer
## 动画名
@export var animation_name: String = "":
	set(v):
		animation_name = v
		if Engine.is_editor_hint() and is_node_ready():
			_preview_frame()

## 是否循环
@export var loop: bool = true

## 播放速度倍率
@export var speed_scale: float = 1.0

## 自动播放
@export var autoplay: bool = false

var _frames: Array = []       # Array[ImageTexture]
var _frame_index: int = 0
var _fps: float = 30.0
var _playing: bool = false
var _elapsed: float = 0.0
var _cache: AVAPCache = null

signal animation_finished()

func _ready() -> void:
	_cache = _get_cache()
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

	texture = _frames[_frame_index]

## 播放动画
func play(anim_name: String = "") -> void:
	if anim_name != "":
		animation_name = anim_name

	if animation_name == "":
		push_warning("AVAPPlayer: 动画名为空")
		return

	_cache = _get_cache()
	if _cache == null:
		push_error("AVAPPlayer: AVAPCache 未找到")
		return

	_frames = await _cache.get_animation(animation_name)
	if _frames.is_empty():
		push_error("AVAPPlayer: 解码失败: " + animation_name)
		return

	# 获取动画信息
	var info := _cache._decoder.get_animation_info(animation_name) if _cache._decoder else {}
	_fps = info.get("fps", 30.0)

	_frame_index = 0
	_elapsed = 0.0
	_playing = true
	texture = _frames[0]

## 停止播放
func stop() -> void:
	_playing = false
	_frame_index = 0
	if _frames.size() > 0:
		texture = _frames[0]

## 暂停
func pause() -> void:
	_playing = false

## 继续
func resume() -> void:
	if _frames.size() > 0:
		_playing = true

## 当前帧索引
func get_current_frame() -> int:
	return _frame_index

## 总帧数
func get_frame_count() -> int:
	return _frames.size()

## 是否正在播放
func is_playing() -> bool:
	return _playing

## 编辑器预览
func _preview_frame() -> void:
	if animation_name == "":
		texture = null
		return
	# 编辑器下只显示占位
	# TODO: 可选加载第一帧预览

## 获取 AVAPCache 单例
func _get_cache() -> AVAPCache:
	# 尝试从 Autoload 获取
	var node := get_node_or_null("/root/AVAPCache")
	if node and node is AVAPCache:
		return node
	# 遍历场景树找
	return null
