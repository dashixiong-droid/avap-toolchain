## AVAP 动画资源
## 继承 Resource，可序列化到 .tscn / .tres
##
## 开发时：直接引用带 alpha 通道的原始视频
## 打包时：按 tag 分组 → binpack → 拆 alpha → 双轨编码
##
## 用法:
##   在 Inspector 里拖入视频文件，设置 tag 和播放参数
##   打包脚本自动扫描、分组、编码
@tool
extends Resource
class_name AVAPResource

## 带 alpha 通道的视频文件路径
@export_file("*.webm", "*.mp4", "*.mov", "*.avi") var video_path: String = ""

## 打包分组标签
## 同 tag 的动画 binpack 到同一个 atlas
## 打包时可按 tag 配置不同的压缩参数
@export var tag: String = "default"

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

## 获取动画名（从文件名推导）
func get_animation_name() -> String:
	if video_path == "":
		return ""
	var name: String = video_path.get_file().get_basename()
	# 去掉 _alpha 后缀（如果有）
	name = name.replace("_alpha", "")
	return name

## 获取显示名（编辑器用）
func _to_string() -> String:
	var anim := get_animation_name()
	if anim != "":
		return "AVAPResource[%s](%s)" % [tag, anim]
	return "AVAPResource(empty)"
