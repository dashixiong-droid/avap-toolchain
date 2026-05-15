## AVAP 路径解析器
## 统一管理"逻辑路径 → 物理路径"的映射
## 开发期和打包期走不同分支，元数据只写逻辑路径
##
## 用法:
##   var resolver = AVAPPathResolver.new()
##   resolver.base_dir = "res://avap_data"           # 元数据所在目录
##   var physical = resolver.resolve("videos/atlas_000.webm")
##
## 外部 ResourceManager 接管:
##   resolver.set_custom_resolver(func(logical): return MyRM.resolve(logical))
extends RefCounted

## 元数据所在目录（逻辑路径前缀），如 "res://avap_data"
var base_dir: String = ""

## 是否为发布模式（打包后运行）
## 自动检测：编辑器内为 false，导出后为 true
var is_release: bool = false

## 外部自定义解析器（callable，接收逻辑路径，返回物理路径）
## 设置后优先级最高，跳过内置逻辑
var _custom_resolver: Callable = Callable()

func _init() -> void:
	is_release = not Engine.is_editor_hint()

## 设置自定义路径解析器
## callable 签名: func(logical_path: String) -> String
## 返回空字符串表示"我不管这个路径，走默认逻辑"
func set_custom_resolver(resolver: Callable) -> void:
	_custom_resolver = resolver

## 解析逻辑路径 → 物理路径
## logical_path: 相对于 base_dir 的路径，如 "videos/atlas_000.webm"
## 返回: 原生解码器可直接使用的物理路径
func resolve(logical_path: String) -> String:
	if logical_path == "":
		return ""
	
	# 1. 外部接管优先
	if _custom_resolver.is_valid():
		var result: String = _custom_resolver.call(logical_path)
		if result != "":
			return result
	
	# 2. 编辑器模式：直接拼 res://
	if not is_release:
		return _resolve_dev(logical_path)
	
	# 3. 发布模式：按平台分发
	return _resolve_release(logical_path)

## 编辑器模式：res:// 直接可用
func _resolve_dev(logical_path: String) -> String:
	var full_path: String = base_dir.path_join(logical_path)
	# 验证文件存在
	if FileAccess.file_exists(full_path):
		return full_path
	# fallback: 可能是绝对路径直接传入
	if FileAccess.file_exists(logical_path):
		return logical_path
	push_warning("AVAPPathResolver: 文件不存在: %s" % full_path)
	return full_path

## 发布模式：按平台解析
func _resolve_release(logical_path: String) -> String:
	if OS.has_feature("android"):
		return _resolve_android(logical_path)
	elif OS.has_feature("ios"):
		return _resolve_ios(logical_path)
	elif OS.has_feature("web"):
		return _resolve_web(logical_path)
	else:
		# Desktop release fallback
		return _resolve_dev(logical_path)

## Android: 视频在 assets/avap_videos/ 或 user://avap_videos/
## MediaExtractor 需要绝对路径，所以需要桥接到 user://
func _resolve_android(logical_path: String) -> String:
	var filename: String = logical_path.get_file()
	var user_path: String = "user://avap_videos/" + filename
	var abs_path: String = OS.get_user_data_dir() + "/avap_videos/" + filename
	
	# 已复制过，直接返回
	if FileAccess.file_exists(user_path):
		return abs_path
	
	# 尝试从 res:// 复制（PCK 内可能还有，也可能没有）
	var res_path: String = base_dir.path_join(logical_path)
	var src := FileAccess.open(res_path, FileAccess.READ)
	if src:
		DirAccess.make_dir_recursive_absolute("user://avap_videos")
		var dst := FileAccess.open(user_path, FileAccess.WRITE)
		if dst:
			dst.store_buffer(src.get_buffer(src.get_length()))
			dst.close()
		src.close()
		print("AVAPPathResolver: 复制 %s → %s" % [res_path, abs_path])
		return abs_path
	
	# 尝试从 assets/avap_videos/ 复制（打包脚本注入的）
	var assets_path: String = "res://avap_videos/" + filename
	src = FileAccess.open(assets_path, FileAccess.READ)
	if src:
		DirAccess.make_dir_recursive_absolute("user://avap_videos")
		var dst := FileAccess.open(user_path, FileAccess.WRITE)
		if dst:
			dst.store_buffer(src.get_buffer(src.get_length()))
			dst.close()
		src.close()
		print("AVAPPathResolver: 从 assets 复制 %s → %s" % [filename, abs_path])
		return abs_path
	
	push_error("AVAPPathResolver: Android 无法访问: %s" % logical_path)
	return abs_path

## iOS: 视频在 App Bundle 的 avap_videos/ 目录
## AVAssetReader 可以直接读 Bundle 绝对路径
func _resolve_ios(logical_path: String) -> String:
	var filename: String = logical_path.get_file()
	# iOS: 打包脚本把视频放到 Bundle 的 avap_videos/ 目录
	# Godot 的 res:// 在 iOS 上映射到 Bundle 根目录
	var bundle_path: String = "res://avap_videos/" + filename
	if FileAccess.file_exists(bundle_path):
		# 转成绝对路径给 AVAssetReader
		return ProjectSettings.globalize_path(bundle_path)
	
	# fallback: 尝试 res:// 原路径
	var res_path: String = base_dir.path_join(logical_path)
	if FileAccess.file_exists(res_path):
		return ProjectSettings.globalize_path(res_path)
	
	push_error("AVAPPathResolver: iOS 无法访问: %s" % logical_path)
	return ProjectSettings.globalize_path(bundle_path)

## Web: 视频在 PCK 内，JS 端从 ArrayBuffer 读取
## Web 平台视频文件保留在 PCK 中（不走外部存储）
func _resolve_web(logical_path: String) -> String:
	var full_path: String = base_dir.path_join(logical_path)
	if FileAccess.file_exists(full_path):
		return full_path
	push_warning("AVAPPathResolver: Web 文件不存在: %s" % full_path)
	return full_path
