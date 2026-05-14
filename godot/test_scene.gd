extends Node2D

func _ready():
	print("=== AVAP C++ Decoder Test ===")
	
	var decoder = AVAPDecoder.new()
	
	# 加载元数据
	var meta_path = "res://test_output/metadata.json"
	if not FileAccess.file_exists(meta_path):
		push_error("元数据文件不存在: " + meta_path)
		# 尝试绝对路径
		meta_path = "/Users/claw/Projects/avap-toolchain/examples/output/metadata.json"
		if not FileAccess.file_exists(meta_path):
			push_error("绝对路径也不存在")
			return
	
	print("加载元数据: ", meta_path)
	decoder.load_metadata(meta_path)
	
	# 列出所有动画
	var anims = decoder.list_animations()
	print("可用动画: ", anims)
	
	if anims.size() == 0:
		push_error("没有找到动画")
		return
	
	# 解码第一个动画
	var anim_name = anims[0]
	print("解码动画: ", anim_name)
	var textures = decoder.decode_animation(anim_name)
	print("解码得到 %d 帧" % textures.size())
	
	if textures.size() > 0:
		# 显示第一帧
		var sprite = Sprite2D.new()
		sprite.texture = textures[0]
		sprite.position = Vector2(400, 300)
		add_child(sprite)
		print("第一帧已显示!")
		
		# 如果有多帧，做简单动画
		if textures.size() > 1:
			_start_animation(sprite, textures)
	
func _start_animation(sprite: Sprite2D, textures: Array) -> void:
	var frame := 0
	while true:
		frame = (frame + 1) % textures.size()
		sprite.texture = textures[frame]
		await get_tree().create_timer(1.0 / 30.0).timeout
