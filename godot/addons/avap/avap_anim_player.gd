## AVAP 动画控制器
## 独立的播放逻辑组件，不继承 Sprite2D。
##
## 循环模式：
##   LOOP     — 正向循环 0→N→0→N...
##   PINGPONG — 正向→反向→正向... 0→N→N-1→1→0→N...
##   ONCE     — 播放一次后停在最后一帧
##   RESTART  — 每次从头重新播放（配合 play() 的 from_frame 参数）
##
## 播放速度：
##   speed_scale 控制播放速率倍率（1.0=原始速度，2.0=两倍速，0.5=半速）
##   也可以在 play() 时指定自定义 fps 覆盖元数据里的帧率
##
## 用法：
##   var player := AVAPAnimPlayer.new()
##   player.setup(cache, "explosion")
##   add_child(player)
##   player.play()                          # 默认 LOOP
##   player.play("slash", LoopMode.PINGPONG)  # pingpong
##   player.play("aura", LoopMode.ONCE, 2.0)  # 两倍速播一次
##   player.play("fire", LoopMode.RESTART, 1.0, 5)  # 从第5帧开始重新循环
class_name AVAPAnimPlayer
extends Node

enum LoopMode {
	LOOP,       ## 正向循环
	PINGPONG,   ## 正向→反向交替
	ONCE,       ## 播放一次停在末帧
	RESTART,    ## 每次从头重新播放
}

signal animation_finished()       ## ONCE 模式播完时触发
signal frame_changed(frame_index: int)  ## 每帧切换

@export var animation_name: String = ""
@export var loop_mode: LoopMode = LoopMode.LOOP
@export var speed_scale: float = 1.0
@export var autoplay: bool = false

var _frames: Array = []       # Array[ImageTexture]
var _frame_index: int = 0
var _fps: float = 30.0        # 元数据里的原始帧率
var _custom_fps: float = -1.0 # play() 时覆盖的帧率，-1 表示用元数据
var _playing: bool = false
var _elapsed: float = 0.0
var _direction: int = 1       # 1=正向, -1=反向（pingpong 用）
var _cache: AVAPCache = null

func _ready() -> void:
	if autoplay and animation_name != "":
		play(animation_name)

func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return

	_elapsed += delta
	var effective_fps := _custom_fps if _custom_fps > 0 else _fps
	var frame_duration := 1.0 / (effective_fps * speed_scale)

	while _elapsed >= frame_duration:
		_elapsed -= frame_duration
		_advance_frame()

	frame_changed.emit(_frame_index)

# ── 帧推进逻辑（根据循环模式）─────────────────────
func _advance_frame() -> void:
	_frame_index += _direction

	var count := _frames.size()

	if count <= 0:
		return

	if loop_mode == LoopMode.LOOP:
		if _frame_index >= count:
			_frame_index = 0
		elif _frame_index < 0:
			_frame_index = count - 1

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
		if _frame_index >= count:
			_frame_index = 0
		elif _frame_index < 0:
			_frame_index = count - 1

# ── 公开接口 ──────────────────────────────────────

## 获取当前帧纹理
func get_current_texture() -> Texture2D:
	if _frames.is_empty() or _frame_index >= _frames.size():
		return null
	return _frames[_frame_index]

## 设置动画源
func setup(cache: AVAPCache, anim_name: String) -> void:
	_cache = cache
	animation_name = anim_name

## 播放动画
## anim_name:    动画名，空字符串则用当前 animation_name
## mode:         循环模式，默认 LOOP
## custom_speed: 播放速度倍率，默认 1.0（-1 表示用当前 speed_scale）
## custom_fps:   覆盖帧率，-1 表示用元数据里的 fps
## from_frame:   从第几帧开始，默认 0
func play(anim_name: String = "", mode: LoopMode = LoopMode.LOOP, custom_speed: float = -1.0, custom_fps: float = -1.0, from_frame: int = 0) -> void:
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

	loop_mode = mode
	_custom_fps = custom_fps
	if custom_speed > 0:
		speed_scale = custom_speed

	_frame_index = clampi(from_frame, 0, _frames.size() - 1)
	_elapsed = 0.0
	_direction = 1
	_playing = true
	frame_changed.emit(_frame_index)

## 停止播放，回到第 0 帧
func stop() -> void:
	_playing = false
	_frame_index = 0
	_direction = 1

## 暂停（保持当前帧）
func pause() -> void:
	_playing = false

## 继续播放（从当前帧继续）
func resume() -> void:
	if _frames.size() > 0:
		_playing = true

## 跳到指定帧（不改变播放状态）
func seek_frame(index: int) -> void:
	_frame_index = clampi(index, 0, _frames.size() - 1)
	frame_changed.emit(_frame_index)

## 获取当前帧索引
func get_current_frame() -> int:
	return _frame_index

## 获取总帧数
func get_frame_count() -> int:
	return _frames.size()

## 是否正在播放
func is_playing() -> bool:
	return _playing

## 获取动画尺寸
func get_animation_size() -> Vector2i:
	if _frames.is_empty():
		return Vector2i.ZERO
	var img: ImageTexture = _frames[0]
	return Vector2i(img.get_width(), img.get_height())

func _find_cache() -> AVAPCache:
	var node := get_node_or_null("/root/AVAPCache")
	if node and node is AVAPCache:
		return node
	return null