## AVAP 示例场景
## 演示如何使用 AVAPCache + AVAPPlayer 播放视频打包特效
##
## 场景设置:
##   1. 将 avap_cache.gd 添加为 Autoload（名称 AVAPCache）
##   2. 将 avap_metadata.json 和 .webm 文件放到 res://vfx/
##   3. 添加此脚本到 Node2D
extends Node2D

@export var metadata_path: String = "res://vfx/avap_metadata.json"
@export var demo_animations: PackedStringArray = ["explosion", "sparkle", "slash"]

var _players: Array[AVAPPlayer] = []
var _current_index: int = 0

func _ready() -> void:
	# 加载元数据
	var cache := _get_cache()
	if cache:
		cache.load_metadata(metadata_path)
		# 预加载所有特效
		cache.preload_all()

	# 创建演示播放器
	_setup_demo_players()

func _setup_demo_players() -> void:
	var x_offset := 0.0
	for anim_name in demo_animations:
		var player := AVAPPlayer.new()
		player.animation_name = anim_name
		player.loop_mode = AVAPAnimPlayer.LoopMode.LOOP
		player.position = Vector2(x_offset, 0)
		add_child(player)
		player.play()
		_players.append(player)
		x_offset += 300.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# 切换到下一个动画
		if _players.size() > 0:
			_players[_current_index].stop()
			_current_index = (_current_index + 1) % _players.size()
			_players[_current_index].play()

func _get_cache() -> AVAPTextureCache:
	var tree := get_tree()
	if tree and tree.root.has_node("AVAPCache"):
		return tree.root.get_node("AVAPCache") as AVAPTextureCache
	return null
