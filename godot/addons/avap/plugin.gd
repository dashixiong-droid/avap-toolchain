@tool
extends EditorPlugin

var _panel: Control = null

func _enter_tree() -> void:
	# 注册 AVAPPlayer 自定义节点类型
	add_custom_type("AVAPPlayer", "Sprite2D", preload("avap_player.gd"), preload("icon.svg"))
	
	# 创建打包面板
	_panel = preload("avap_panel.tscn").instantiate()
	_panel.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _panel)

func _exit_tree() -> void:
	remove_custom_type("AVAPPlayer")
	if _panel:
		remove_control_from_docks(_panel)
		_panel.free()