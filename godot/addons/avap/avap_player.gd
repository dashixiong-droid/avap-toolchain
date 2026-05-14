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

@export var loop: bool = true
@export var speed_scale: float = 1.0
@export var autoplay: bool = false

var _anim: AVAPAnimPlayer = null

func _ready() -> void:
	_anim = AVAPAnimPlayer.new()
	_anim.animation_name = animation_name
	_anim.loop = loop
	_anim.speed_scale = speed_scale
	_anim.autoplay = autoplay
	add_child(_anim)
	_anim.frame_changed.connect(_on_frame_changed)

func play(anim_name: String = "") -> void:
	_anim.play(anim_name)

func stop() -> void:
	_anim.stop()
	if _anim.get_frame_count() > 0:
		texture = _anim.get_current_texture()

func pause() -> void:
	_anim.pause()

func resume() -> void:
	_anim.resume()

func is_playing() -> bool:
	return _anim.is_playing()

func get_anim_player() -> AVAPAnimPlayer:
	return _anim

func _on_frame_changed(frame_index: int) -> void:
	texture = _anim.get_current_texture()

func _preview_frame() -> void:
	if animation_name == "":
		texture = null
