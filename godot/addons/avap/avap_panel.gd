@tool
extends Control

var plugin: EditorPlugin = null

## Tag 配置
var _tags: Dictionary = {}
var _tag_config_path: String = "res://addons/avap/avap_tags.cfg"

## 扫描结果: anim_name -> {path, tag, node_path}
var _scanned_anims: Dictionary = {}

## 打包路径
var _pack_root: String = "res://avap_res"
var _pack_packed: String = "res://avap_res/packed"

## 预览状态
var _preview_cache: AVAPTextureCache = null
var _preview_player: AVAPAnimPlayer = null
var _preview_anim_names: PackedStringArray = []
var _preview_current: int = 0

# ── Tag 管理 ──
@onready var _tag_list: ItemList = %TagList
@onready var _btn_add_tag: Button = %BtnAddTag
@onready var _btn_del_tag: Button = %BtnDelTag
@onready var _tag_name_edit: LineEdit = %TagNameEdit
@onready var _tag_label_edit: LineEdit = %TagLabelEdit
@onready var _tag_atlas_size: SpinBox = %TagAtlasSize
@onready var _tag_fps: SpinBox = %TagFps
@onready var _tag_dual: CheckBox = %TagDualTrack
@onready var _tag_crf: SpinBox = %TagCrf
@onready var _tag_speed: SpinBox = %TagSpeed
@onready var _btn_save_tags: Button = %BtnSaveTags

# ── 打包 ──
@onready var _anim_tree: Tree = %AnimTree
@onready var _btn_scan: Button = %BtnScan
@onready var _btn_pack: Button = %BtnPack
@onready var _pack_progress: ProgressBar = %PackProgress
@onready var _pack_log: RichTextLabel = %PackLog

# ── 预览 ──
@onready var _preview_anim_list: ItemList = %PreviewAnimList
@onready var _preview_rect: TextureRect = %PreviewRect
@onready var _btn_play: Button = %BtnPlay
@onready var _btn_stop: Button = %BtnStop
@onready var _btn_prev: Button = %BtnPrev
@onready var _btn_next: Button = %BtnNext
@onready var _lbl_status: Label = %LblStatus

func _ready() -> void:
	_load_tags()
	_refresh_tag_list()

# ══════════════════════════════════════════════════
# ── Tag 管理 ─────────────────────────────────────
# ══════════════════════════════════════════════════

func _load_tags() -> void:
	_tags.clear()
	var cfg := ConfigFile.new()
	if cfg.load(_tag_config_path) == OK:
		for section: String in cfg.get_sections():
			_tags[section] = {
				"label": cfg.get_value(section, "label", section),
				"atlas_size": cfg.get_value(section, "atlas_size", 2048),
				"fps": cfg.get_value(section, "fps", 30),
				"dual_track": cfg.get_value(section, "dual_track", true),
				"crf": cfg.get_value(section, "crf", 25),
				"speed": cfg.get_value(section, "speed", 4),
			}
	if not _tags.has("default"):
		_tags["default"] = {"label": "默认", "atlas_size": 2048, "fps": 30, "dual_track": true, "crf": 25, "speed": 4}

func _save_tags() -> void:
	var cfg := ConfigFile.new()
	for tag: String in _tags:
		var d: Dictionary = _tags[tag]
		cfg.set_value(tag, "label", d.get("label", tag))
		cfg.set_value(tag, "atlas_size", d.get("atlas_size", 2048))
		cfg.set_value(tag, "fps", d.get("fps", 30))
		cfg.set_value(tag, "dual_track", d.get("dual_track", true))
		cfg.set_value(tag, "crf", d.get("crf", 25))
		cfg.set_value(tag, "speed", d.get("speed", 4))
	cfg.save(_tag_config_path)
	_log_pack("Tag 配置已保存")

func _refresh_tag_list() -> void:
	_tag_list.clear()
	for tag: String in _tags:
		var label: String = _tags[tag].get("label", tag)
		_tag_list.add_item("%s [%s]" % [tag, label])

func _on_tag_list_item_selected(index: int) -> void:
	var tag: String = _tags.keys()[index]
	var d: Dictionary = _tags[tag]
	_tag_name_edit.text = tag
	_tag_label_edit.text = d.get("label", tag)
	_tag_atlas_size.value = d.get("atlas_size", 2048)
	_tag_fps.value = d.get("fps", 30)
	_tag_dual.button_pressed = d.get("dual_track", true)
	_tag_crf.value = d.get("crf", 25)
	_tag_speed.value = d.get("speed", 4)

func _on_btn_add_tag_pressed() -> void:
	var tag: String = _tag_name_edit.text.strip_edges().to_lower()
	if tag.is_empty() or _tags.has(tag): return
	_tags[tag] = {
		"label": _tag_label_edit.text.strip_edges() if _tag_label_edit.text.strip_edges() != "" else tag,
		"atlas_size": int(_tag_atlas_size.value),
		"fps": int(_tag_fps.value),
		"dual_track": _tag_dual.button_pressed,
		"crf": int(_tag_crf.value),
		"speed": int(_tag_speed.value),
	}
	_refresh_tag_list()
	_save_tags()

func _on_btn_del_tag_pressed() -> void:
	var sel: PackedInt32Array = _tag_list.get_selected_items()
	if sel.is_empty(): return
	var tag: String = _tags.keys()[sel[0]]
	if tag == "default": return
	_tags.erase(tag)
	_refresh_tag_list()
	_save_tags()

func _on_btn_save_tags_pressed() -> void:
	var sel: PackedInt32Array = _tag_list.get_selected_items()
	if sel.is_empty(): return
	var old_tag: String = _tags.keys()[sel[0]]
	var new_tag: String = _tag_name_edit.text.strip_edges().to_lower()
	if new_tag.is_empty(): return
	if new_tag != old_tag:
		_tags.erase(old_tag)
	_tags[new_tag] = {
		"label": _tag_label_edit.text.strip_edges(),
		"atlas_size": int(_tag_atlas_size.value),
		"fps": int(_tag_fps.value),
		"dual_track": _tag_dual.button_pressed,
		"crf": int(_tag_crf.value),
		"speed": int(_tag_speed.value),
	}
	_refresh_tag_list()
	_save_tags()

func get_tag_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for tag: String in _tags: names.append(tag)
	return names

# ══════════════════════════════════════════════════
# ── 扫描 ─────────────────────────────────────────
# ══════════════════════════════════════════════════

func _on_btn_scan_pressed() -> void:
	_scanned_anims.clear()
	_anim_tree.clear()
	var root: TreeItem = _anim_tree.create_item()
	root.set_text(0, "动画资源")
	
	if not plugin: return
	var ei: EditorInterface = plugin.get_editor_interface()
	var edited_scene: Node = ei.get_edited_scene_root()
	if edited_scene:
		_scan_node_recursive(edited_scene, root)
	
	_log_pack("扫描完成: %d 个动画" % _scanned_anims.size())

func _scan_node_recursive(node: Node, parent: TreeItem) -> void:
	if node is AVAPAnimPlayer or node is AVAPPlayer:
		_register_anim_from_node(node, parent)
	for child: Node in node.get_children():
		_scan_node_recursive(child, parent)

func _register_anim_from_node(node: Node, parent: TreeItem) -> void:
	var anim_name: String = ""
	var tag: String = "default"
	
	if node is AVAPAnimPlayer:
		anim_name = node.animation_name
		if node.has_meta("avap_tag"): tag = node.get_meta("avap_tag")
	elif node is AVAPPlayer:
		anim_name = node.animation_name
		if node.has_meta("avap_tag"): tag = node.get_meta("avap_tag")
	
	if anim_name.is_empty(): return
	
	var asset_path: String = "res://assets/%s" % anim_name
	_scanned_anims[anim_name] = {"path": asset_path, "tag": tag, "node_path": str(node.get_path())}
	
	var item: TreeItem = _anim_tree.create_item(parent)
	item.set_text(0, anim_name)
	item.set_text(1, tag)
	item.set_text(2, asset_path)

# ══════════════════════════════════════════════════
# ── 打包 ─────────────────────────────────────────
# ══════════════════════════════════════════════════

func _on_btn_pack_pressed() -> void:
	if _scanned_anims.is_empty():
		_log_pack("[color=red]请先扫描[/color]")
		return
	
	_btn_pack.disabled = true
	_btn_pack.text = "打包中..."
	_pack_progress.visible = true
	_pack_progress.value = 0
	
	# 1. 版本管理：packed → history.N
	_rotate_packed_dir()
	
	# 2. 按 tag 分组
	var groups: Dictionary = {}
	for anim_name: String in _scanned_anims:
		var tag: String = _scanned_anims[anim_name].get("tag", "default")
		if not groups.has(tag): groups[tag] = []
		groups[tag].append(anim_name)
	
	_log_pack("按 tag 分组: %d 组" % groups.size())
	for tag: String in groups:
		_log_pack("  [%s]: %s" % [tag, ", ".join(groups[tag])])
	
	# 3. 逐 tag 打包
	var all_ok: bool = true
	for tag: String in groups:
		var tag_cfg: Dictionary = _tags.get(tag, _tags["default"])
		if not _pack_tag(tag, groups[tag], tag_cfg):
			all_ok = false
	
	if all_ok:
		_pack_progress.value = 100
		_log_pack("[color=green]✅ 全部打包完成[/color]")
		if plugin:
			plugin.get_editor_interface().get_resource_filesystem().scan()
		_load_preview()
	else:
		_log_pack("[color=red]❌ 打包出错[/color]")
	
	_btn_pack.disabled = false
	_btn_pack.text = "📦 打包"
	_pack_progress.visible = false

func _rotate_packed_dir() -> void:
	var abs_packed: String = ProjectSettings.globalize_path(_pack_packed)
	if not DirAccess.dir_exists_absolute(abs_packed): return
	
	var idx: int = 1
	var abs_root: String = ProjectSettings.globalize_path(_pack_root)
	while DirAccess.dir_exists_absolute(abs_root + "/history.%d" % idx):
		idx += 1
	
	var backup: String = abs_root + "/history.%d" % idx
	if DirAccess.rename_absolute(abs_packed, backup) == OK:
		_log_pack("旧产物备份 → history.%d" % idx)

func _pack_tag(tag: String, anim_names: Array, tag_cfg: Dictionary) -> bool:
	_log_pack("打包 [%s] (%d 动画)..." % [tag, anim_names.size()])
	
	# 收集素材绝对路径，symlink 到临时目录
	var tmp_dir: String = ProjectSettings.globalize_path("res://.avap_tmp_%s" % tag)
	_remove_dir(tmp_dir)
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	
	for anim_name: String in anim_names:
		var res_path: String = _scanned_anims[anim_name].get("path", "res://assets/%s" % anim_name)
		var abs_src: String = ProjectSettings.globalize_path(res_path)
		if DirAccess.dir_exists_absolute(abs_src):
			OS.execute("ln", ["-s", abs_src, tmp_dir + "/" + anim_name])
		else:
			_log_pack("[color=yellow]跳过: %s[/color]" % res_path)
	
	# 输出文件名用 tag 命名: default.webm, default_alpha.webm, default.json
	var abs_out_dir: String = ProjectSettings.globalize_path(_pack_packed)
	DirAccess.make_dir_recursive_absolute(abs_out_dir)
	
	var args: PackedStringArray = [
		"-m", "avap", "pack", tmp_dir, abs_out_dir,
		"--atlas-size", str(int(tag_cfg.get("atlas_size", 2048))),
		"--fps", str(int(tag_cfg.get("fps", 30))),
		"--crf", str(int(tag_cfg.get("crf", 25))),
		"--speed", str(int(tag_cfg.get("speed", 4))),
		"--output-prefix", tag,
	]
	if tag_cfg.get("dual_track", true):
		args.append("--dual-track")
	
	var output: PackedStringArray = []
	var exit_code: int = OS.execute("python3", args, output, false)
	for line: String in output:
		_pack_log.append_text(line + "\n")
	
	_remove_dir(tmp_dir)
	
	if exit_code != 0:
		_log_pack("[color=red][%s] 失败 (exit: %d)[/color]" % [tag, exit_code])
		return false
	
	_log_pack("[%s] 完成" % tag)
	return true

func _remove_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		OS.execute("rm", ["-rf", path])

# ══════════════════════════════════════════════════
# ── 预览 ─────────────────────────────────────────
# ══════════════════════════════════════════════════

func _load_preview() -> void:
	if _preview_cache:
		_preview_cache.release_all()
	if _preview_player:
		_preview_player.queue_free()
		_preview_player = null
	_preview_anim_names.clear()
	_preview_anim_list.clear()
	_preview_rect.texture = null
	
	_preview_cache = AVAPTextureCache.new()
	_preview_cache._ready()
	
	# 扫描 packed/ 下所有 <tag>.json
	var da := DirAccess.open(ProjectSettings.globalize_path(_pack_packed))
	if da:
		da.list_dir_begin()
		var fname := da.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				var meta_path: String = _pack_packed.path_join(fname)
				_preview_cache.load_metadata(meta_path)
			fname = da.get_next()
		da.list_dir_end()
	
	_preview_anim_names = _preview_cache.list_available()
	if _preview_anim_names.is_empty():
		_lbl_status.text = "无可用动画"
		return
	
	for name: String in _preview_anim_names:
		_preview_anim_list.add_item(name)
	
	_set_preview_controls(true)
	_lbl_status.text = "%d 个动画就绪" % _preview_anim_names.size()
	_preview_anim_list.select(0)
	_on_preview_anim_selected(0)

func _on_preview_anim_selected(index: int) -> void:
	if index < 0 or index >= _preview_anim_names.size(): return
	_preview_current = index
	var anim_name: String = _preview_anim_names[index]
	_lbl_status.text = "播放: %s" % anim_name
	
	if _preview_player:
		_preview_player.stop()
		_preview_player.queue_free()
	
	_preview_player = AVAPAnimPlayer.new()
	add_child(_preview_player)
	_preview_player.setup(_preview_cache, anim_name)
	_preview_player.frame_changed.connect(_on_frame_changed)
	_preview_player.play(anim_name, AVAPAnimPlayer.LoopMode.LOOP)

func _on_frame_changed(_frame_index: int) -> void:
	if _preview_player and _preview_rect:
		_preview_rect.texture = _preview_player.get_current_texture()

func _on_btn_play_pressed() -> void:
	if _preview_player: _preview_player.resume()

func _on_btn_stop_pressed() -> void:
	if _preview_player: _preview_player.stop()
	_preview_rect.texture = null

func _on_btn_prev_pressed() -> void:
	var idx: int = maxi(0, _preview_current - 1)
	_preview_anim_list.select(idx)
	_on_preview_anim_selected(idx)

func _on_btn_next_pressed() -> void:
	var idx: int = mini(_preview_anim_names.size() - 1, _preview_current + 1)
	_preview_anim_list.select(idx)
	_on_preview_anim_selected(idx)

func _set_preview_controls(enabled: bool) -> void:
	_btn_play.disabled = not enabled
	_btn_stop.disabled = not enabled
	_btn_prev.disabled = not enabled
	_btn_next.disabled = not enabled

# ── 工具 ──────────────────────────────────────────

func _log_pack(text: String) -> void:
	if _pack_log: _pack_log.append_text(text + "\n")