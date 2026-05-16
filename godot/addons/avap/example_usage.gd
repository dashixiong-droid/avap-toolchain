## AVAP 使用示例
extends Node2D

var _cache: AVAPTextureCache = null

func _ready() -> void:
	_cache = get_node("/root/AVAPCache")
	_cache.load_metadata("res://avap/metadata.json")

	# ── LOOP: 正向循环（默认）────────────────────
	var loop_player := AVAPPlayer.new()
	loop_player.animation_name = "aura_loop"
	loop_player.loop_mode = AVAPAnimPlayer.LoopMode.LOOP
	loop_player.position = Vector2(150, 200)
	loop_player.autoplay = true
	add_child(loop_player)

	# ── PINGPONG: 正向→反向交替 ────────────────────
	var pingpong := AVAPPlayer.new()
	pingpong.position = Vector2(350, 200)
	pingpong.play("explosion", AVAPAnimPlayer.LoopMode.PINGPONG)
	add_child(pingpong)

	# ── ONCE: 播一次停住 ──────────────────────────
	var once := AVAPPlayer.new()
	once.position = Vector2(550, 200)
	once.play("slash", AVAPAnimPlayer.LoopMode.ONCE)
	once.get_anim_player().animation_finished.connect(func(): print("slash 播完了"))
	add_child(once)

	# ── RESTART + 自定义速度 ──────────────────────
	var fast := AVAPPlayer.new()
	fast.position = Vector2(750, 200)
	fast.play("fire_ring", AVAPAnimPlayer.LoopMode.RESTART, 2.0)  # 两倍速
	add_child(fast)

	# ── 从第5帧开始播放 ───────────────────────────
	var from_mid := AVAPPlayer.new()
	from_mid.position = Vector2(150, 450)
	from_mid.play("heal_effect", AVAPAnimPlayer.LoopMode.LOOP, 1.0, -1.0, 5)
	add_child(from_mid)

	# ── AVAPAnimPlayer + TextureRect (UI) ─────────
	var rect := TextureRect.new()
	rect.position = Vector2(350, 400)
	rect.size = Vector2(128, 128)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(rect)

	var anim := AVAPAnimPlayer.new()
	anim.setup(_cache, "sparkle")
	anim.frame_changed.connect(func(idx): rect.texture = anim.get_current_texture())
	rect.add_child(anim)
	anim.play("", AVAPAnimPlayer.LoopMode.PINGPONG, 0.5)  # 半速 pingpong

	# ── 手动控制 ─────────────────────────────────
	var frames := await _cache.get_frames("shield")
	if not frames.is_empty():
		var sprite := Sprite2D.new()
		sprite.position = Vector2(550, 450)
		sprite.texture = frames[0]
		add_child(sprite)
		# 自己做帧切换...
