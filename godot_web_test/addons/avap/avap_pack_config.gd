## AVAP 打包配置
## 继承 Resource，可序列化到 .tres
## 项目级全局配置 + 按 tag 覆盖
##
## 用法:
##   在项目设置里创建一个 AVAPPackConfig.tres
##   全局设置默认压缩参数
##   tag_overrides 里按 tag 覆盖特定参数
@tool
extends Resource
class_name AVAPPackConfig

## 全局压缩配置
@export_group("Global Compression")

## VP9 CRF 值（0-63，越低质量越高，默认 25）
@export_range(0, 63) var vp9_crf: int = 25

## VP9 编码速度（0-8，越慢质量越高，默认 4）
@export_range(0, 8) var vp9_speed: int = 4

## H.264 CRF 值（0-51，越低质量越高，默认 18）
@export_range(0, 51) var h264_crf: int = 18

## Atlas 最大尺寸
@export var max_atlas_size: int = 2048

## 是否生成 iOS H.264 版本
@export var generate_ios_h264: bool = true

## 按 tag 覆盖压缩配置
## key = tag 名，value = Dictionary 覆盖字段
## 例: {"cutscene": {"vp9_crf": 15, "vp9_speed": 1}, "ui": {"vp9_crf": 30}}
@export var tag_overrides: Dictionary = {}

## 获取指定 tag 的最终压缩配置（全局 + tag 覆盖）
func get_config_for_tag(tag_name: String) -> Dictionary:
	var config := {
		"vp9_crf": vp9_crf,
		"vp9_speed": vp9_speed,
		"h264_crf": h264_crf,
		"max_atlas_size": max_atlas_size,
		"generate_ios_h264": generate_ios_h264,
	}
	if tag_overrides.has(tag_name):
		var override: Dictionary = tag_overrides[tag_name]
		for key in override:
			config[key] = override[key]
	return config

func _to_string() -> String:
	return "AVAPPackConfig(crf=%d, tags=%s)" % [vp9_crf, str(tag_overrides.keys())]
