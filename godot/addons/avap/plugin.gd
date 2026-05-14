@tool
extends EditorPlugin


func _enter_tree() -> void:
	# 添加自定义类型，让 AVAPPlayer 出现在添加节点菜单
	add_custom_type("AVAPPlayer", "Sprite2D", preload("avap_player.gd"), preload("icon.svg"))


func _exit_tree() -> void:
	remove_custom_type("AVAPPlayer")
