# AVAP Godot 插件

AVAP 的 Godot 4.x 运行时插件，提供视频打包特效的解码、缓存和播放功能。

当前为 **GDScript 实现**（调用 FFmpeg 子进程解码），适合快速验证和桌面端使用。后续可替换为 GDExtension C++ 解码器以获得更好的移动端性能。

## 安装

1. 将 `addons/avap/` 目录复制到你的 Godot 项目的 `res://addons/avap/`
2. 在项目设置 → Autoload 中添加 `avap_cache.gd`，名称设为 `AVAPCache`
3. 在项目设置 → Plugins 中启用 AVAP 插件
4. 确保目标平台安装了 FFmpeg（桌面端需要，移动端需替换为 GDExtension）

## 架构

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  AVAPPlayer  │────▶│  AVAPCache    │────▶│  AVAPDecoder  │
│  (Sprite2D)  │     │  (Autoload)   │     │  (FFmpeg)     │
│              │     │               │     │               │
│  播放控制     │     │  纹理缓存     │     │  视频解码      │
│  帧切换      │     │  LRU 淘汰     │     │  双轨合并      │
└─────────────┘     └──────────────┘     └──────────────┘
							│
					┌───────┴────────┐
					│  AVAPMetadata   │
					│  元数据解析      │
					└────────────────┘
```

### 模块说明

**avap_metadata.gd** — 元数据加载器
- 解析 `avap_metadata.json`
- 提供动画查询接口（`find_animation`、`list_animations`）
- 内部类 `AVAPAtlas` 和 `AVAPAnimation` 封装元数据结构

**avap_decoder.gd** — 视频解码器
- 调用 FFmpeg 子进程解码指定动画的帧
- 单轨模式：`-c:v libvpx-vp9` 保留 alpha
- 双轨模式：分别解码 RGB 和 Alpha 视频，逐像素合并为 RGBA
- 解码输出到临时目录的 PNG 序列，加载后自动清理

**avap_cache.gd** — 纹理缓存（Autoload 单例）
- 维护动画名 → `Array[Texture2D]` 的映射
- 缓存未命中时自动触发解码
- 支持 LRU 淘汰（可配置最大条目数）
- 子线程解码 + 主线程创建纹理，减少卡顿

**avap_player.gd** — 播放器节点（继承 Sprite2D）
- 导出属性：`animation`、`loop`、`speed_scale`、`autoplay`
- 按原始帧率自动切换纹理
- 信号：`animation_finished()`、`frame_changed(index)`
- 支持播放/暂停/停止/跳帧

## 使用方法

### 1. 准备资产

用 AVAP 工具链打包特效：

```bash
python -m avap pack my_effects res://vfx --dual-track --crf 25
```

将输出的 `.webm` 文件和 `avap_metadata.json` 放到 Godot 项目的 `res://vfx/` 目录。

### 2. 加载元数据

在游戏启动时（如 Main 脚本的 `_ready`）：

```gdscript
func _ready():
	AVAPCache.load_metadata("res://vfx/avap_metadata.json")
```

### 3. 预加载特效

在场景切换或加载画面时预解码常用特效：

```gdscript
# 预加载战斗常用特效
AVAPCache.preload(["explosion", "slash", "heal_effect"])

# 或预加载全部
AVAPCache.preload_all()
```

### 4. 播放特效

**方式 A：使用 AVAPPlayer 节点**

```gdscript
var player = AVAPPlayer.new()
player.animation = "explosion"
player.loop = false
add_child(player)
player.play()
player.animation_finished.connect(func(): player.queue_free())
```

**方式 B：手动从缓存获取纹理**

```gdscript
var frames = await AVAPCache.get_frames("explosion")
sprite.texture = frames[0]

# 播放逻辑自行控制
var _frame_index = 0
func _process(delta):
	_frame_index = (_frame_index + 1) % frames.size()
	sprite.texture = frames[_frame_index]
```

### 5. 缓存管理

```gdscript
# 释放不常用的特效
AVAPCache.release("old_effect")

# 设置 LRU 上限（最多缓存 50 个动画）
AVAPCache.max_cache_entries = 50

# 查看已缓存的动画
print(AVAPCache.list_cached())
```

## 注意事项

- **FFmpeg 依赖**：当前 GDScript 实现依赖系统 FFmpeg，桌面端需要安装，移动端不可用
- **移动端方案**：需替换为 GDExtension C++ 解码器（内嵌 FFmpeg 或使用平台原生解码器）
- **主线程阻塞**：`ImageTexture.create_from_image()` 必须在主线程，大量帧解码后会短暂卡顿。建议预加载
- **双轨合并**：`_merge_rgb_alpha` 逐像素操作较慢，C++ 实现可大幅加速
- **路径**：`res://` 路径在导出后可能不同，建议用 `ProjectSettings.globalize_path()` 转换

## 后续优化方向

- **GDExtension C++ 解码器**：内嵌 FFmpeg，子线程解码，消除 FFmpeg 子进程依赖
- **批量纹理上传**：分帧创建 ImageTexture，分散到多帧渲染周期
- **GPU 合并**：用 Shader 直接在 GPU 上合并 RGB + Alpha 纹理，避免 CPU 逐像素操作
- **异步加载 Signal**：解码完成发 Signal，支持 await 协程
