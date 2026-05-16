## AVAP 生产模式测试
## 从打包产物 (metadata + atlas webm) 解码并播放
## 按数字键 1-7 切换动画，空格暂停/继续，R 重播
extends Node2D

var _cache: AVAPTextureCache = null
var _player: AVAPPlayer = null
var _anim_names: PackedStringArray = []
var _current: int = 0

func _ready() -> void:
	_cache = get_node("/root/AVAPCache")
	if _cache == null:
		push_error("AVAPCache Autoload 未找到")
		return

	# 生产模式：加载打包产物
	_cache.load_metadata("res://test_output/avap_metadata.json")

	_anim_names = _cache.list_available()
	if _anim_names.is_empty():
		push_error("没有可用动画")
		return

	print("可用动画: ", _anim_names)

	_player = AVAPPlayer.new()
	_player.position = Vector2(576, 300)
	add_child(_player)
	_play_current()

func _input(event: InputEvent) -> void:
	if _player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < _anim_names.size():
			_current = idx
			_play_current()
		elif event.keycode == KEY_SPACE:
			if _player.is_playing():
				_player.pause()
			else:
				_player.resume()
		elif event.keycode == KEY_R:
			_player.play(_anim_names[_current])

func _play_current() -> void:
	var name: String = _anim_names[_current]
	print("播放: ", name)
	_player.play(name, AVAPAnimPlayer.LoopMode.LOOP)
