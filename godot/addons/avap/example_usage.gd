## AVAP 使用示例 — 三种调用方式
##
## 1. AVAPPlayer (Sprite2D 封装) — 最简单，拖到场景即可
## 2. AVAPAnimPlayer (独立组件) — 任意节点组合使用
## 3. 直接调 AVAPCache — 完全手动控制

extends Node2D

var _cache: AVAPCache = null

func _ready() -> void:
	_cache = get_node("/root/AVAPCache")
	_cache.load_metadata("res://avap/metadata.json")

	# ── 方式1: AVAPPlayer (Sprite2D) ──────────────
	_example_sprite_player()

	# ── 方式2: AVAPAnimPlayer (任意节点) ──────────
	_example_anim_player()

	# ── 方式3: 直接拿帧数据 ─────────────────────
	_example_manual()

# ── 方式1: AVAPPlayer ────────────────────────────
func _example_sprite_player() -> void:
	var player := AVAPPlayer.new()
	player.animation_name = "explosion"
	player.position = Vector2(200, 200)
	player.autoplay = true
	add_child(player)

# ── 方式2: AVAPAnimPlayer + 任意节点 ─────────────
func _example_anim_player() -> void:
	# 比如用在 TextureRect (UI) 上
	var rect := TextureRect.new()
	rect.position = Vector2(400, 200)
	rect.size = Vector2(256, 256)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(rect)

	var anim := AVAPAnimPlayer.new()
	anim.setup(_cache, "slash")
	anim.frame_changed.connect(func(idx): rect.texture = anim.get_current_texture())
	rect.add_child(anim)
	anim.play()

# ── 方式3: 手动控制 ─────────────────────────────
func _example_manual() -> void:
	# 直接拿帧数组，自己决定怎么用
	var frames := await _cache.get_animation("sparkle")
	if frames.is_empty():
		return

	var sprite := Sprite2D.new()
	sprite.position = Vector2(600, 200)
	sprite.texture = frames[0]
	add_child(sprite)

	# 简单帧切换
	var idx := 0
	while true:
		idx = (idx + 1) % frames.size()
		sprite.texture = frames[idx]
		await get_tree().create_timer(1.0 / 30.0).timeout
