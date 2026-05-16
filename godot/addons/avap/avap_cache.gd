## AVAP 动画缓存（Autoload 单例）
## 封装原生 AVAPDecoder，提供全局访问点。
##
## 开发模式两种加载方式:
##   load_video()      — 直接解码视频文件（MOV/ProRes 4444 带 alpha）
##   load_frames_dir() — 从 PNG 序列帧目录加载
## 生产模式:
##   load_metadata()   — 从打包后的 metadata + atlas 视频解码
##
## 用法:
##   # 开发模式 - 视频
##   AVAPCache.load_video("res://assets_videos/explosion.mov", "explosion")
##   # 开发模式 - PNG 序列帧
##   AVAPCache.load_frames_dir("res://assets/explosion", "explosion")
##   # 生产模式
##   AVAPCache.load_metadata("res://vfx/avap_metadata.json")
class_name AVAPTextureCache
extends Node

## 单例引用
static var _instance: AVAPTextureCache = null

## 原生解码器
var _decoder: AVAPDecoder = null

## 开发模式缓存: anim_name -> Array[ImageTexture]
var _dev_cache: Dictionary = {}

## 是否为开发模式
var _dev_mode: bool = false

func _ready() -> void:
	_instance = self
	_decoder = AVAPDecoder.new()
	add_child(_decoder)

## ── 开发模式 ──────────────────────────────────────────

## 直接解码视频文件（支持 MOV/ProRes 4444 带 alpha）
## anim_name 自定义（默认取文件名）
func load_video(video_path: String, anim_name: String = "") -> void:
	_dev_mode = true
	if anim_name == "":
		anim_name = video_path.get_file().get_basename()
	var textures: Array = _decoder.decode_video(video_path)
	if textures.is_empty():
		push_error("AVAP: 视频解码失败: " + video_path)
		return
	_dev_cache[anim_name] = textures
	print("AVAP: 开发模式(视频)加载 '%s' (%d帧)" % [anim_name, textures.size()])

## 从 PNG 序列帧目录加载动画
## dir_path: res:// 路径，如 "res://assets/explosion"
## anim_name: 动画名称，默认取目录名
func load_frames_dir(dir_path: String, anim_name: String = "") -> void:
	_dev_mode = true
	if anim_name == "":
		anim_name = dir_path.trim_suffix("/").get_file()
	
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	var da := DirAccess.open(abs_dir)
	if da == null:
		push_error("AVAP: 无法打开目录: " + dir_path)
		return
	
	# 收集 PNG 文件并排序
	var files: PackedStringArray = []
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if fname.ends_with(".png"):
			files.append(fname)
		fname = da.get_next()
	da.list_dir_end()
	files.sort()
	
	if files.is_empty():
		push_error("AVAP: 目录无 PNG 文件: " + dir_path)
		return
	
	# 逐帧加载为 ImageTexture
	var textures: Array = []
	for f: String in files:
		var img_path: String = dir_path.path_join(f)
		var img := Image.load_from_file(img_path)
		if img == null:
			push_warning("AVAP: 跳过无法加载的帧: " + f)
			continue
		var tex := ImageTexture.create_from_image(img)
		textures.append(tex)
	
	if textures.is_empty():
		push_error("AVAP: 无有效帧: " + dir_path)
		return
	
	_dev_cache[anim_name] = textures
	print("AVAP: 开发模式(PNG)加载 '%s' (%d帧)" % [anim_name, textures.size()])

## 批量加载视频：传入 {anim_name: video_path} 字典
func load_video_batch(videos: Dictionary) -> void:
	for name: String in videos:
		load_video(videos[name], name)

## 批量加载序列帧：传入 {anim_name: dir_path} 字典
func load_frames_batch(dirs: Dictionary) -> void:
	for name: String in dirs:
		load_frames_dir(dirs[name], name)

## ── 生产模式 ──────────────────────────────────────────

## 加载元数据文件（打包后使用）
func load_metadata(path: String) -> void:
	_dev_mode = false
	var abs_path := ProjectSettings.globalize_path(path)
	_decoder.load_metadata(abs_path)
	print("AVAP: 生产模式加载元数据 %s" % path)

## ── 通用接口 ──────────────────────────────────────────

## 获取动画帧纹理
func get_frames(anim_name: String) -> Array:
	if _dev_mode:
		if _dev_cache.has(anim_name):
			return _dev_cache[anim_name]
		push_error("AVAP: 开发模式下动画未加载: " + anim_name)
		return []
	else:
		return _decoder.decode(anim_name)

## 列出所有可用动画
func list_available() -> PackedStringArray:
	if _dev_mode:
		var names: PackedStringArray = []
		for name: String in _dev_cache:
			names.append(name)
		return names
	return _decoder.list_animations()

## 释放指定动画的缓存
func release(anim_name: String) -> void:
	if _dev_mode:
		_dev_cache.erase(anim_name)
		return
	_decoder.release(anim_name)

## 释放所有缓存
func release_all() -> void:
	if _dev_mode:
		_dev_cache.clear()
		return
	_decoder.release_all()
