# AVAP — Animation Video Asset Pack

将多个带透明通道的动画特效离线打包为视频文件，运行时按需解码到纹理缓存。

**核心思路**：用视频当压缩容器，利用 VP9 帧间压缩把序列帧体积压到 1%–10%。播放时一次性解码所需动画的全部帧为纹理数组并缓存，后续播放即普通纹理切换，零额外解码开销。

**双轨灰阶方案**：RGB 视频和 Alpha 灰度视频分离编码（均为 VP9 + yuv420p），Alpha 精度比单轨 yuva420p 提升 6 倍，体积反而更小。

## 压缩效果

| | 原始 PNG 序列 | 单轨 yuva420p | 双轨灰阶 |
|---|---|---|---|
| 体积 | 1832 KB | 81 KB (4.4%) | **120 KB (6.5%)** |
| Alpha max diff | — | 62 | **7** |
| Alpha mean diff | — | 20.1 | **1.9** |

> 7 个特效（explosion/sparkle/aura_loop/slash/heal_effect/shield/fire_ring），1024×1024 atlas，CRF 25

## 安装

**依赖**：Python 3.9+、FFmpeg（需含 libvpx）、Pillow

```bash
# macOS
brew install ffmpeg
pip install Pillow

# 验证
python -m avap info
```

## 快速开始

```bash
# 1. 生成测试素材（7 种程序化特效）
python vfx_gen.py my_effects

# 2. 打包为双轨 WebM（推荐）
python -m avap pack my_effects my_output --dual-track --atlas-size 1024 --crf 25

# 3. 查看打包结果
python -m avap list my_output/avap_metadata.json

# 4. 解码验证
python -m avap decode my_output/avap_metadata.json explosion sparkle -o decoded_preview
```

## CLI 命令

### `scan` — 扫描素材目录

```bash
python -m avap scan <input_dir>
```

列出目录下所有 RGBA 图像序列（PNG/WebP），自动检测帧率和尺寸。

### `pack` — 完整打包流程

```bash
python -m avap pack <input_dir> [output_dir] [options]
```

**参数**：
- `--atlas-size N` — Atlas 画布尺寸，默认 2048
- `--fps N` — 输出帧率，默认 30
- `--crf N` — VP9 CRF 值（20–30，越小质量越高），默认 25
- `--speed N` — 编码速度 0–8（0 最慢最高质量），默认 0
- `--threads N` — 编码线程数，默认 4
- `--dual-track` — 使用灰阶双轨编码（推荐）

### `decode` — 解码指定动画

```bash
python -m avap decode <metadata.json> <animation_name> [...] [-o output_dir]
```

从打包视频中提取指定动画的帧序列，输出为 PNG。双轨模式自动合并 RGB + Alpha。

### `list` — 列出可用动画

```bash
python -m avap list <metadata.json>
```

### `info` — 打印工具链版本和依赖信息

```bash
python -m avap info
```

## 项目结构

```
avap-toolchain/
├── avap/                  # CLI 入口包
│   ├── __init__.py        # 版本号
│   ├── __main__.py        # python -m avap 入口
│   └── cli.py             # 命令行解析与流程串联
├── binpack.py             # 动态矩形装箱（MaxRects 算法）
├── scanner.py             # 素材扫描（PNG 序列 → AnimationAsset）
├── scheduler.py           # 打包调度器（逐帧合成 + 生命周期管理）
├── encoder.py             # 视频编码（FFmpeg VP9，支持单轨/双轨）
├── decoder.py             # 运行时解码（帧精确 seek + 裁切 + 双轨合并）
├── metadata_schema.py     # 元数据结构（AnimationInfo/AtlasMeta/AVAPMetadata）
├── vfx_gen.py             # 程序化特效生成器（7 种测试特效）
├── godot/                 # Godot 4.x 插件
│   └── addons/avap/
│       ├── avap_metadata.gd  # 元数据加载器
│       ├── avap_decoder.gd   # 视频解码器（FFmpeg 子进程）
│       ├── avap_cache.gd     # 纹理缓存（Autoload 单例）
│       ├── avap_player.gd    # 播放器节点（Sprite2D）
│       ├── plugin.gd         # 编辑器插件入口
│       ├── plugin.cfg        # 插件配置
│       ├── icon.svg          # 节点图标
│       ├── example_scene.gd  # 使用示例
│       └── README.md         # 插件文档
└── examples/              # 示例素材和输出
    ├── assets/            # 7 个特效的源帧 PNG
    └── output/            # 打包输出（.webm + metadata.json）
```

## 模块说明

### binpack.py — 动态矩形装箱

MaxRects 算法实现，支持动态 insert/remove。核心创新：利用动画生命周期差异——播完的动画从画布移除腾出空间，新动画填入空隙，atlas 利用率远高于静态拼图。

- `even_align=True` 时自动将 x/y/w/h 对齐到偶数，避免 yuv420p 色度子采样偏移
- `best_fit()` 选择最适合当前空闲区域的动画
- `remove()` 后自动 merge 相邻空闲区域

### scanner.py — 素材扫描

遍历目录，将 RGBA 图像序列识别为 `AnimationAsset`。自动检测帧率（从目录名或文件数量推断）和尺寸。

### scheduler.py — 打包调度器

核心调度逻辑：将多个动画素材动态装箱到 atlas 画布，逐帧合成 PNG 序列。

- 初始化 BinpackAtlas 画布，best_fit 选出最适合的动画
- 逐帧渲染：将所有活跃动画的当前帧写入画布
- 动画播完后 remove 腾出空间，再 best_fit 填入新动画
- 双轨模式：分别输出 RGB（straight alpha）和 Alpha 灰度帧序列
- 画布满后开新 atlas，直到全部打包完成

### encoder.py — 视频编码

调用 FFmpeg 将帧序列编码为 WebM。

- **单轨**：`-pix_fmt yuva420p`，一个视频包含 RGB + Alpha
- **双轨**：RGB 视频用 `-pix_fmt yuv420p`，Alpha 灰度视频用 `-pix_fmt yuv420p`
- 支持 `EncodeOptions` 配置 codec/crf/speed/threads/gop_size
- 编码完成后自动清理中间帧目录

### decoder.py — 运行时解码

从 atlas 视频中提取指定动画的帧序列。

- 使用 FFmpeg `select` 滤镜精确选帧 + `crop` 滤镜裁切区域
- **单轨**：必须用 `-c:v libvpx-vp9` 解码器（默认解码器会丢弃 VP9 alpha side data）
- **双轨**：分别解码 RGB 和 Alpha 视频，Pillow 合并为 RGBA 帧
- `decode_batch()` 支持批量解码，每个动画独立子目录

### metadata_schema.py — 元数据结构

- `AnimationInfo` — 单个动画的索引信息（帧区间、rect、原始尺寸）
- `AtlasMeta` — 单个 atlas 的信息（视频文件、编码参数、动画列表）
- `AVAPMetadata` — 完整打包元数据（版本、atlases 列表）
- `EncodeOptions` — 编码参数（codec/pix_fmt/crf/speed/threads/gop_size）

### vfx_gen.py — 测试特效生成器

程序化生成 7 种典型游戏特效的 RGBA 帧序列，用于验证打包流程：

| 特效 | 尺寸 | 帧数 | 说明 |
|---|---|---|---|
| explosion | 256×256 | 30 | 中心扩散 + 颜色渐变 + 透明衰减 |
| aura_loop | 256×256 | 40 | 旋转光环 + 脉冲（循环） |
| sparkle | 64×64 | 12 | 十字光芒 + 缩放 |
| fire_ring | 192×192 | 24 | 环形火焰 + 上升火星 |
| heal_effect | 200×200 | 30 | 上升光柱 + 十字 + 粒子 |
| slash | 320×320 | 18 | 弧形刀光 + 拖尾 |
| shield | 288×288 | 20 | 六边形网格 + 脉冲 |

## 元数据格式

打包输出 `avap_metadata.json`，结构示例：

```json
{
  "version": 1,
  "atlases": [{
    "index": 0,
    "video_file": "atlas_000.webm",
    "alpha_video_file": "atlas_000_alpha.webm",
    "width": 1024,
    "height": 1024,
    "fps": 30,
    "total_frames": 40,
    "encode_options": { "codec": "libvpx-vp9", "crf": 25, "speed": 0, "threads": 4 },
    "animations": {
      "explosion": {
        "atlas_index": 0,
        "start_frame": 0,
        "end_frame": 29,
        "rect": { "x": 256, "y": 608, "w": 256, "h": 256 },
        "orig_size": { "w": 256, "h": 256 },
        "frame_count": 30,
        "fps": 30.0
      }
    }
  }]
}
```

- `rect` — 动画在 atlas 中的裁切区域（偶数对齐）
- `orig_size` — 原始尺寸（与 rect 不同时说明做了偶数对齐扩展）
- `alpha_video_file` — 双轨模式下的 Alpha 灰度视频文件名

## 运行时性能

### 两阶段模型

AVAP 的运行时消耗分两个阶段，压力完全不同：

- **解码阶段**（一次性）：从视频解码帧 → 创建纹理 → 缓存，有 CPU/IO 压力
- **播放阶段**（持续）：`Sprite2D.texture = frames[i]`，纯显存引用切换，**零额外开销**

### 解码耗时估算（ARM64 移动端）

| 特效规模 | 解码耗时 | 显存占用 | 体感 |
|---|---|---|---|
| 小（64×64, 12帧） | ~5ms | 0.2MB | 无感 |
| 中（256×256, 30帧） | ~30–60ms | 7.5MB | 微卡 |
| 大（512×512, 60帧） | ~100–200ms | 60MB | 明显卡 |
| 同时 3 个中特效 | ~100–180ms | 22MB | 需预加载 |

> VP9 解码约 1–2ms/帧（ARM big core），比 PNG decode 慢 2–3 倍，但只发生在首次加载

### 双轨额外开销

- 解码两个视频（RGB + Alpha），seek 两次，解码量翻倍
- 合并步骤：逐像素 `RGBA = (R, G, B, A_alpha)`，纯内存操作，30帧约 2–3ms

### 主线程阻塞问题

Godot 的 `ImageTexture.create_from_image()` 必须在主线程执行。解码 30 帧 256×256 会占主线程 30–60ms，帧率瞬间掉到 16fps。

**解决方案**：

1. **子线程解码 + 主线程上传** — GDExtension 用 `WorkerThreadPool` 做 FFmpeg decode → Image 数组，完成后发 Signal 通知主线程批量创建纹理，主线程阻塞从 60ms 降到 5–10ms
2. **预加载** — 在场景切换/加载画面时预解码常用特效，进战斗后缓存已就绪
3. **分批纹理上传** — 每帧创建 1–2 个 ImageTexture，分散到多帧渲染周期，延迟几帧开始播放但完全无卡顿
4. **LRU 缓存淘汰** — 256×256×30帧 = 7.5MB 显存，手机 2GB 上限可缓存约 260 个中等特效，播完不常用的自动释放

### 与传统序列帧对比

| | 传统 PNG 序列帧 | AVAP 视频打包 |
|---|---|---|
| 包体 | 每个 PNG 单独存储 | WebM 压缩，省 90%+ |
| 加载 | 逐个 PNG decode，IO 分散 | 一次 seek+decode，IO 集中 |
| 首次解码 | PNG decode ≈ 0.5ms/帧 | VP9 decode ≈ 1–2ms/帧 |
| 播放性能 | 纹理切换 | 纹理切换（完全等同） |
| 显存占用 | 一样 | 一样 |

**结论**：VP9 解码比 PNG 慢 2–3 倍，但只发生在首次加载。包体省 90%+，播放性能完全等同。手机端用子线程解码 + 预加载即可消除卡顿。

## Godot 集成

`godot/addons/avap/` 目录包含完整的 Godot 4.x 插件：

| 文件 | 说明 |
|---|---|
| `avap_metadata.gd` | 元数据加载器，解析 avap_metadata.json |
| `avap_decoder.gd` | 视频解码器，调用 FFmpeg 子进程 |
| `avap_cache.gd` | 纹理缓存（Autoload），LRU 淘汰 |
| `avap_player.gd` | 播放器节点（Sprite2D），帧率控制 |
| `plugin.gd` / `plugin.cfg` | 编辑器插件注册 |
| `example_scene.gd` | 使用示例 |

快速上手：

```gdscript
# 1. 加载元数据
AVAPCache.load_metadata("res://vfx/avap_metadata.json")

# 2. 预加载
AVAPCache.preload(["explosion", "slash"])

# 3. 播放
var player = AVAPPlayer.new()
player.animation = "explosion"
add_child(player)
player.play()
```

详见 [godot/addons/avap/README.md](godot/addons/avap/README.md)。

## 注意事项

- **VP9 Alpha 解码**：必须用 `-c:v libvpx-vp9` 解码器，FFmpeg 默认 VP9 解码器会丢弃 alpha side data
- **偶数对齐**：binpack 的 x/y/w/h 全部偶数对齐，避免 yuv420p 色度子采样偏移
- **Straight Alpha**：双轨模式下 RGB 帧保留原始颜色值，不乘 alpha（避免 premultiplied 亮度偏暗）
- **移动端**：VP9 解码由 CPU 完成，建议在加载画面预解码常用特效

## License

MIT
