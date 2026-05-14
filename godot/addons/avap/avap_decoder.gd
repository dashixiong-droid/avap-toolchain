## AVAP 解码器
## 调用 FFmpeg 子进程从 atlas 视频中解码指定动画帧
## 支持单轨（yuva420p）和双轨（RGB + Alpha 灰度）模式
##
## 解码流程：FFmpeg 输出 PNG 序列到临时目录 → Image.load_from_file → 合并 → 返回
class_name AVAPDecoder
extends RefCounted


signal decode_completed(anim_name: String, images: Array[Image])

var _ffmpeg_path: String = "ffmpeg"
var _tmp_base: String = ""


func _init(ffmpeg_path: String = "ffmpeg") -> void:
	_ffmpeg_path = ffmpeg_path
	_tmp_base = OS.get_cache_dir().path_join("avap_decode")


## 解码指定动画的所有帧，返回 Image 数组
## 可在子线程中调用（Image.load_from_file 不需要主线程）
func decode_animation(
	anim: AVAPMetadata.AVAPAnimation,
	atlas: AVAPMetadata.AVAPAtlas,
	base_dir: String,
) -> Array[Image]:
	var video_path: String = _resolve_path(base_dir, atlas.video_file)
	var alpha_path: String = _resolve_path(base_dir, atlas.alpha_video_file) if atlas.alpha_video_file != "" else ""

	if atlas.alpha_video_file != "":
		return _decode_dual_track(anim, video_path, alpha_path)
	else:
		return _decode_single_track(anim, video_path)


## 异步解码（在子线程执行，完成后发 signal 回主线程）
func decode_async(
	anim_name: String,
	anim: AVAPMetadata.AVAPAnimation,
	atlas: AVAPMetadata.AVAPAtlas,
	base_dir: String,
) -> void:
	var images := decode_animation(anim, atlas, base_dir)
	decode_completed.emit(anim_name, images)


## 单轨解码：VP9 + yuva420p，必须用 -c:v libvpx-vp9
func _decode_single_track(anim: AVAPMetadata.AVAPAnimation, video_path: String) -> Array[Image]:
	var tmp_dir := _make_tmp_dir("single_%d" % anim.atlas_index)
	var output_pattern := tmp_dir.path_join("frame_%06d.png")

	var vf := "select=between(n\\,%d\\,%d),crop=%d:%d:%d:%d" % [
		anim.start_frame, anim.end_frame,
		anim.rect_w, anim.rect_h, anim.rect_x, anim.rect_y,
	]

	var args: PackedStringArray = [
		"-c:v", "libvpx-vp9",  # 必须用 libvpx 解码器保留 alpha
		"-i", video_path,
		"-vf", vf,
		"-vsync", "vfr",
		"-loglevel", "error",
		"-y",
		output_pattern,
	]

	var ec := OS.execute(_ffmpeg_path, args, [], false)
	if ec != 0:
		push_error("AVAP: 单轨解码失败 (exit=%d): %s" % [ec, video_path])
		return []

	var images := _load_png_sequence(tmp_dir)
	_cleanup_dir(tmp_dir)
	return images


## 双轨解码：分别解码 RGB 和 Alpha 视频到临时目录，合并为 RGBA
func _decode_dual_track(
	anim: AVAPMetadata.AVAPAnimation,
	rgb_path: String,
	alpha_path: String,
) -> Array[Image]:
	var tmp_rgb := _make_tmp_dir("rgb_%d" % anim.atlas_index)
	var tmp_alpha := _make_tmp_dir("alpha_%d" % anim.atlas_index)

	var vf := "select=between(n\\,%d\\,%d),crop=%d:%d:%d:%d" % [
		anim.start_frame, anim.end_frame,
		anim.rect_w, anim.rect_h, anim.rect_x, anim.rect_y,
	]

	# 解码 RGB
	var rgb_args: PackedStringArray = [
		"-i", rgb_path,
		"-vf", vf,
		"-vsync", "vfr",
		"-loglevel", "error",
		"-y",
		tmp_rgb.path_join("frame_%06d.png"),
	]
	var ec1 := OS.execute(_ffmpeg_path, rgb_args, [], false)
	if ec1 != 0:
		push_error("AVAP: RGB 解码失败 (exit=%d): %s" % [ec1, rgb_path])
		_cleanup_dir(tmp_rgb)
		_cleanup_dir(tmp_alpha)
		return []

	# 解码 Alpha 灰度
	var alpha_args: PackedStringArray = [
		"-i", alpha_path,
		"-vf", vf,
		"-vsync", "vfr",
		"-loglevel", "error",
		"-y",
		tmp_alpha.path_join("frame_%06d.png"),
	]
	var ec2 := OS.execute(_ffmpeg_path, alpha_args, [], false)
	if ec2 != 0:
		push_error("AVAP: Alpha 解码失败 (exit=%d): %s" % [ec2, alpha_path])
		_cleanup_dir(tmp_rgb)
		_cleanup_dir(tmp_alpha)
		return []

	# 加载并合并
	var rgb_images := _load_png_sequence(tmp_rgb)
	var alpha_images := _load_png_sequence(tmp_alpha)

	if rgb_images.size() != alpha_images.size():
		push_warning("AVAP: RGB帧数(%d) != Alpha帧数(%d)" % [rgb_images.size(), alpha_images.size()])

	var result: Array[Image] = []
	var count := mini(rgb_images.size(), alpha_images.size())
	for i in count:
		result.append(_merge_rgb_alpha(rgb_images[i], alpha_images[i]))

	_cleanup_dir(tmp_rgb)
	_cleanup_dir(tmp_alpha)
	return result


## 合并 RGB 图像和 Alpha 灰度图为 RGBA
func _merge_rgb_alpha(rgb: Image, alpha: Image) -> Image:
	var w := rgb.get_width()
	var h := rgb.get_height()
	var result := Image.create(w, h, false, Image.FORMAT_RGBA8)

	# 确保 alpha 图像尺寸匹配
	var alpha_resized := alpha
	if alpha.get_width() != w or alpha.get_height() != h:
		alpha_resized = alpha.duplicate()
		alpha_resized.resize(w, h, Image.INTERPOLATE_NEAREST)

	# 逐像素合并: RGBA = (R, G, B, A_gray)
	for y in h:
		for x in w:
			var c := rgb.get_pixel(x, y)
			var a := alpha_resized.get_pixel(x, y).r  # 灰度图取 R 通道即 alpha
			result.set_pixel(x, y, Color(c.r, c.g, c.b, a))

	return result


## 从目录加载 PNG 序列，按文件名排序
func _load_png_sequence(dir: String) -> Array[Image]:
	var images: Array[Image] = []
	var da := DirAccess.open(dir)
	if da == null:
		return images

	var files: PackedStringArray = []
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if fname.ends_with(".png"):
			files.append(fname)
		fname = da.get_next()
	da.list_dir_end()

	files.sort()

	for f in files:
		var img := Image.load_from_file(dir.path_join(f))
		if img != null:
			images.append(img)
		else:
			push_warning("AVAP: 无法加载帧: %s" % f)

	return images


## 创建临时目录
func _make_tmp_dir(subdir: String) -> String:
	var path := _tmp_base.path_join(subdir)
	DirAccess.make_dir_recursive_absolute(path)
	return path


## 清理临时目录
func _cleanup_dir(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		da.remove(fname)
		fname = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(dir)


## 解析相对路径
func _resolve_path(base_dir: String, filename: String) -> String:
	if filename.is_absolute_path():
		return filename
	return base_dir.path_join(filename)