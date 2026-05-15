## AVAP 动画资源
## 继承 Resource，可序列化到 .tscn / .tres
## 在编辑器里拖拽赋值，标记此动画走 AVAP 打包管线
##
## 用法:
##   var res = AVAPResource.new()
##   res.metadata_path = "res://effects/fire/avap_metadata.json"
##   res.animation_name = "fire_ring"
@tool
extends Resource
class_name AVAPResource

## 元数据文件路径（res:// 开头）
@export_file("*.json") var metadata_path: String = ""

## 动画名称（对应 metadata 里的 animations 键名）
@export var animation_name: String = ""

## 循环模式
enum LoopMode {
	LOOP,
	PINGPONG,
	ONCE,
	RESTART,
}
@export var loop_mode: LoopMode = LoopMode.LOOP

## 播放速度
@export var speed_scale: float = 1.0

## 自动播放
@export var autoplay: bool = false

## 获取显示名（编辑器用）
func _to_string() -> String:
	if animation_name != "":
		return "AVAPResource(%s)" % animation_name
	return "AVAPResource(empty)"
