## AVAP 动画控制器
## 独立播放逻辑组件。
##
## 循环模式：LOOP / PINGPONG / ONCE / RESTART
## 速度控制：speed_scale 或 play() 的 custom_speed/custom_fps
extends Node

enum LoopMode {
	LOOP,
	PINGPONG,
	ONCE,
	RESTART,
}

signal animation_finished()
signal frame_changed(frame_index: int)

@export var animation_name: String = ""
@export var loop_mode: LoopMode = LoopMode.LOOP
@export var speed_scale: float = 1.0
@export var autoplay: bool = false

var _frames: Array = []
var _frame_index: int = 0
var _fps: float = 30.0
var _custom_fps: float = -1.0
var _playing: bool = false
var _elapsed: float = 0.0
var _direction: int = 1
var _cache: Node = null

func _ready() -> void:
	if autoplay and animation_name != "":
		play(animation_name)

func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return
	_elapsed += delta
	var effective_fps: float = _custom_fps if _custom_fps > 0 else _fps
	var frame_duration: float = 1.0 / (effective_fps * speed_scale)
	while _elapsed >= frame_duration:
		_elapsed -= frame_duration
		_advance_frame()
	frame_changed.emit(_frame_index)

func _advance_frame() -> void:
	var count: int = _frames.size()
	if count <= 0:
		return
	_frame_index += _direction
	if loop_mode == LoopMode.LOOP:
		if _frame_index >= count: _frame_index = 0
		elif _frame_index < 0: _frame_index = count - 1
	elif loop_mode == LoopMode.PINGPONG:
		if _frame_index >= count:
			_frame_index = count - 2
			_direction = -1
		elif _frame_index < 0:
			_frame_index = 1
			_direction = 1
	elif loop_mode == LoopMode.ONCE:
		if _direction == 1 and _frame_index >= count:
			_frame_index = count - 1
			_playing = false
			animation_finished.emit()
			return
		elif _direction == -1 and _frame_index < 0:
			_frame_index = 0
			_playing = false
			animation_finished.emit()
			return
	elif loop_mode == LoopMode.RESTART:
		if _frame_index >= count: _frame_index = 0
		elif _frame_index < 0: _frame_index = count - 1

func get_current_texture() -> Texture2D:
	if _frames.is_empty() or _frame_index >= _frames.size():
		return null
	return _frames[_frame_index]

func setup(cache: Node, anim_name: String) -> void:
	_cache = cache
	animation_name = anim_name

func play(anim_name: String = "", mode: LoopMode = LoopMode.LOOP, custom_speed: float = -1.0, custom_fps: float = -1.0, from_frame: int = 0) -> void:
	if anim_name != "":
		animation_name = anim_name
	if animation_name == "":
		return
	if _cache == null:
		_cache = _find_cache()
	if _cache == null:
		push_error("AVAPAnimPlayer: cache 未找到")
		return
	_frames = await _cache.get_animation(animation_name)
	if _frames.is_empty():
		push_error("AVAPAnimPlayer: 解码失败: " + animation_name)
		return
	var info: Dictionary = {}
	if _cache._decoder:
		info = _cache._decoder.get_animation_info(animation_name)
	_fps = info.get("fps", 30.0)
	loop_mode = mode
	_custom_fps = custom_fps
	if custom_speed > 0:
		speed_scale = custom_speed
	_frame_index = clampi(from_frame, 0, _frames.size() - 1)
	_elapsed = 0.0
	_direction = 1
	_playing = true
	frame_changed.emit(_frame_index)

func stop() -> void:
	_playing = false
	_frame_index = 0
	_direction = 1

func pause() -> void:
	_playing = false

func resume() -> void:
	if _frames.size() > 0:
		_playing = true

func seek_frame(index: int) -> void:
	_frame_index = clampi(index, 0, max(_frames.size() - 1, 0))
	frame_changed.emit(_frame_index)

func get_current_frame() -> int:
	return _frame_index

func get_frame_count() -> int:
	return _frames.size()

func is_playing() -> bool:
	return _playing

func _find_cache() -> Node:
	var node = get_node_or_null("/root/AVAPCache")
	if node:
		return node
	return null