## AVAP 播放器节点（Sprite2D 封装）
## 继承 Sprite2D，内部用 AVAPAnimPlayer 驱动帧切换。
##
## 如果需要更灵活的控制（非 Sprite2D 场景），
## 直接用 AVAPAnimPlayer + 监听 frame_changed 信号。
@tool
extends Sprite2D
class_name AVAPPlayer

@export var animation_name: String = "":
	set(v):
		animation_name = v
		if Engine.is_editor_hint() and is_node_ready():
			_preview_frame()

@export var loop_mode: AVAPAnimPlayer.LoopMode = AVAPAnimPlayer.LoopMode.LOOP
@export var speed_scale: float = 1.0
@export var autoplay: bool = false

var _anim: AVAPAnimPlayer = null

func _ready() -> void:
	_anim = AVAPAnimPlayer.new()
	_anim.animation_name = animation_name
	_anim.loop_mode = loop_mode
	_anim.speed_scale = speed_scale
	_anim.autoplay = autoplay
	add_child(_anim)
	_anim.frame_changed.connect(_on_frame_changed)

## 播放动画
## anim_name:    动画名
## mode:         循环模式 (LOOP/PINGPONG/ONCE/RESTART)
## custom_speed: 播放速度倍率
## custom_fps:   覆盖帧率 (-1=用元数据)
## from_frame:   起始帧
func play(anim_name: String = "", mode: AVAPAnimPlayer.LoopMode = AVAPAnimPlayer.LoopMode.LOOP, custom_speed: float = -1.0, custom_fps: float = -1.0, from_frame: int = 0) -> void:
	_anim.play(anim_name, mode, custom_speed, custom_fps, from_frame)

func stop() -> void:
	_anim.stop()
	texture = _anim.get_current_texture()

func pause() -> void:
	_anim.pause()

func resume() -> void:
	_anim.resume()

func seek_frame(index: int) -> void:
	_anim.seek_frame(index)

func is_playing() -> bool:
	return _anim.is_playing()

func get_anim_player() -> AVAPAnimPlayer:
	return _anim

func _on_frame_changed(frame_index: int) -> void:
	texture = _anim.get_current_texture()

func _preview_frame() -> void:
	if animation_name == "":
		texture = null