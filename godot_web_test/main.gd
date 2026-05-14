## AVAP WebGL2 测试主场景
extends Node2D

var _cache: Node = null
var _players: Array = []

func _ready() -> void:
	print("=== AVAP WebGL2 Test ===")
	print("Platform: ", OS.get_name())
	print("Web: ", OS.has_feature("web"))

	_cache = get_node("/root/AVAPCache")
	if _cache == null:
		push_error("AVAPCache autoload 未找到")
		return

	var ok: bool = _cache.load_metadata("res://avap_data/avap_metadata.json")
	if not ok:
		push_error("元数据加载失败")
		return

	var anims: PackedStringArray = _cache.list_animations()
	print("可用动画: ", anims)

	_create_test_grid(anims)

func _create_test_grid(anims: PackedStringArray) -> void:
	var cols: int = 3
	var cell_w: int = 280
	var cell_h: int = 220
	var start_x: int = 40
	var start_y: int = 40

	for i in range(anims.size()):
		var anim_name: String = anims[i]
		var col: int = i % cols
		var row: int = i / cols
		var x: float = start_x + col * cell_w
		var y: float = start_y + row * cell_h

		var label := Label.new()
		label.text = anim_name
		label.position = Vector2(x, y)
		label.add_theme_font_size_override("font_size", 14)
		add_child(label)

		var sprite := Sprite2D.new()
		sprite.position = Vector2(x + 100, y + 100)
		sprite.scale = Vector2(0.5, 0.5)
		add_child(sprite)

		var anim_script := load("res://addons/avap/avap_anim_player.gd")
		var anim := Node.new()
		anim.set_script(anim_script)
		anim.setup(_cache, anim_name)
		sprite.add_child(anim)
		anim.frame_changed.connect(func(idx): sprite.texture = anim.get_current_texture())
		anim.play(anim_name)
		_players.append(anim)