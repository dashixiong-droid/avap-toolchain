## AVAP 元数据加载器
## 解析 avap_metadata.json，提供动画查询接口
class_name AVAPMetadata
extends RefCounted


var version: int = 1
var atlases: Array[AVAPAtlas] = []


static func load_from_file(path: String) -> AVAPMetadata:
	var meta := AVAPMetadata.new()
	if not FileAccess.file_exists(path):
		push_error("AVAP: 元数据文件不存在: %s" % path)
		return meta

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("AVAP: 无法打开元数据文件: %s" % path)
		return meta

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("AVAP: JSON 解析失败: %s (line %d)" % [path, json.get_error_line()])
		return meta

	var data: Dictionary = json.get_data()
	meta.version = data.get("version", 1)

	for atlas_data: Dictionary in data.get("atlases", []):
		var atlas := AVAPAtlas.new()
		atlas.index = atlas_data.get("index", 0)
		atlas.video_file = atlas_data.get("video_file", "")
		atlas.alpha_video_file = atlas_data.get("alpha_video_file", "")
		atlas.width = atlas_data.get("width", 1024)
		atlas.height = atlas_data.get("height", 1024)
		atlas.fps = atlas_data.get("fps", 30.0)
		atlas.total_frames = atlas_data.get("total_frames", 0)

		for anim_name: String in atlas_data.get("animations", {}):
			var anim_data: Dictionary = atlas_data["animations"][anim_name]
			var anim := AVAPAnimation.new()
			anim.name = anim_name
			anim.atlas_index = anim_data.get("atlas_index", 0)
			anim.start_frame = anim_data.get("start_frame", 0)
			anim.end_frame = anim_data.get("end_frame", 0)
			anim.frame_count = anim_data.get("frame_count", 0)
			anim.fps = anim_data.get("fps", 30.0)

			# rect 字段
			var rect: Dictionary = anim_data.get("rect", {})
			anim.rect_x = rect.get("x", 0)
			anim.rect_y = rect.get("y", 0)
			anim.rect_w = rect.get("w", 0)
			anim.rect_h = rect.get("h", 0)

			# orig_size 字段
			var orig: Dictionary = anim_data.get("orig_size", {})
			anim.orig_w = orig.get("w", anim.rect_w)
			anim.orig_h = orig.get("h", anim.rect_h)

			atlas.animations[anim_name] = anim

		meta.atlases.append(atlas)

	return meta


func find_animation(anim_name: String) -> AVAPAnimation:
	for atlas: AVAPAtlas in atlases:
		if atlas.animations.has(anim_name):
			return atlas.animations[anim_name]
	return null


func list_animations() -> PackedStringArray:
	var names: PackedStringArray = []
	for atlas: AVAPAtlas in atlases:
		names.append_array(atlas.animations.keys())
	return names


func get_atlas(index: int) -> AVAPAtlas:
	for atlas: AVAPAtlas in atlases:
		if atlas.index == index:
			return atlas
	return null


## 单个 Atlas 信息
class AVAPAtlas:
	extends RefCounted
	var index: int = 0
	var video_file: String = ""
	var alpha_video_file: String = ""
	var width: int = 1024
	var height: int = 1024
	var fps: float = 30.0
	var total_frames: int = 0
	var animations: Dictionary = {}  # String -> AVAPAnimation


## 单个动画信息
class AVAPAnimation:
	extends RefCounted
	var name: String = ""
	var atlas_index: int = 0
	var start_frame: int = 0
	var end_frame: int = 0
	var frame_count: int = 0
	var fps: float = 30.0
	var rect_x: int = 0
	var rect_y: int = 0
	var rect_w: int = 0
	var rect_h: int = 0
	var orig_w: int = 0
	var orig_h: int = 0

	var is_dual_track: bool:
		get: return atlas_index >= 0  # 由外部设置

	func get_duration() -> float:
		if fps <= 0:
			return 0.0
		return float(frame_count) / fps
