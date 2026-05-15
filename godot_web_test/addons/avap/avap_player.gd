@tool
extends Sprite2D

enum LoopMode {
	LOOP,
	PINGPONG,
	ONCE,
	RESTART,
}

## AVAP 动画资源引用（编辑器里拖拽赋值，序列化到 .tscn）
@export var avap: AVAPResource = null:
	set(v):
		avap = v
		if avap and Engine.is_editor_hint():
			animation_name = avap.animation_name
			loop_mode = avap.loop_mode
			speed_scale = avap.speed_scale
			autoplay = avap.autoplay

## 兼容：直接设置动画名（不通过 AVAPResource）
@export var animation_name: String = "":
	set(v):
		animation_name = v
		if Engine.is_editor_hint() and is_node_ready():
			texture = null

@export var loop_mode: LoopMode = LoopMode.LOOP
@export var speed_scale: float = 1.0
@export var autoplay: bool = false

var _anim: Node = null

func _ready() -> void:
	var script := load("res://addons/avap/avap_anim_player.gd")
	_anim = Node.new()
	_anim.set_script(script)
	add_child(_anim)
	_anim.frame_changed.connect(_on_frame_changed)
	
	# 优先从 AVAPResource 读取
	if avap:
		animation_name = avap.animation_name
		loop_mode = avap.loop_mode
		speed_scale = avap.speed_scale
		autoplay = avap.autoplay
		_anim.animation_name = animation_name
		_anim.loop_mode = loop_mode
		_anim.speed_scale = speed_scale
		_anim.autoplay = autoplay
	else:
		_anim.animation_name = animation_name
		_anim.loop_mode = loop_mode
		_anim.speed_scale = speed_scale
		_anim.autoplay = autoplay

func play(anim_name: String = "", mode: LoopMode = LoopMode.LOOP, custom_speed: float = -1.0, custom_fps: float = -1.0, from_frame: int = 0) -> void:
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

func get_anim_player() -> Node:
	return _anim

func _on_frame_changed(frame_index: int) -> void:
	texture = _anim.get_current_texture()
