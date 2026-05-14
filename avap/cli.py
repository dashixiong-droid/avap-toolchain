"""
AVAP CLI 主入口 — 串联扫描、调度、编码、解码全流程

Usage:
    python -m avap scan <input_dir>
    python -m avap pack <input_dir> [output_dir]
    python -m avap decode <metadata_json> <animation_name> [...]
    python -m avap list <metadata_json>
    python -m avap info
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

# 将项目根目录加入 sys.path，使无包结构的模块可被导入
_PROJECT_ROOT = str(Path(__file__).resolve().parent.parent)
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

from scanner import AssetScanner
from scheduler import PackScheduler
from encoder import VideoEncoder
from decoder import AVAPDecoder
from metadata_schema import AVAPMetadata
import avap


# ── 命令实现 ────────────────────────────────────────────────

def cmd_scan(args: argparse.Namespace) -> None:
    """扫描素材目录，打印发现的动画列表"""
    scanner = AssetScanner()
    assets = scanner.scan(args.input_dir)

    if not assets:
        print("未发现动画素材")
        return

    print(f"发现 {len(assets)} 个动画素材:\n")
    for a in assets:
        print(f"  {a.name:30s}  {a.width}x{a.height}  "
              f"{a.frame_count}帧  {a.fps:.1f}fps  {a.dir_path}")


def cmd_pack(args: argparse.Namespace) -> None:
    """完整打包流程：扫描 → 调度 → 编码 → 输出元数据"""
    input_dir = args.input_dir
    output_dir = args.output_dir or str(Path(input_dir) / "avap_output")
    atlas_size = args.atlas_size
    fps = args.fps
    dual_track = args.dual_track

    from metadata_schema import EncodeOptions
    encode_opts = EncodeOptions(
        crf=args.crf,
        speed=args.speed,
        threads=args.threads,
    )

    # 1. 扫描
    print("[1/3] 扫描素材...")
    scanner = AssetScanner()
    assets = scanner.scan(input_dir)
    if not assets:
        print("未发现动画素材，退出")
        return
    print(f"  发现 {len(assets)} 个动画素材")

    # 2. 调度 + 逐帧渲染
    print("[2/3] 调度打包...")
    scheduler = PackScheduler(
        atlas_width=atlas_size, atlas_height=atlas_size, fps=fps,
        dual_track=dual_track,
    )
    metadata = scheduler.pack(assets, output_dir)
    print(f"  生成 {len(metadata.atlases)} 个 atlas")

    # 3. 编码
    print("[3/3] 编码视频...")
    encoder = VideoEncoder()
    for atlas in metadata.atlases:
        frames_dir = str(Path(output_dir) / f"atlas_{atlas.index:03d}")

        if dual_track:
            # 双轨编码: RGB 视频 + Alpha 灰度视频
            rgb_path = str(Path(output_dir) / f"atlas_{atlas.index:03d}.webm")
            alpha_path = str(Path(output_dir) / f"atlas_{atlas.index:03d}_alpha.webm")

            atlas.video_file = f"atlas_{atlas.index:03d}.webm"
            atlas.alpha_video_file = f"atlas_{atlas.index:03d}_alpha.webm"
            atlas.encode_options = encode_opts

            def _progress(p: float) -> None:
                pct = int(p * 100)
                print(f"\r  atlas_{atlas.index}: {pct}%", end="", flush=True)

            rgb_result, alpha_result = encoder.encode_dual(
                frames_dir, rgb_path, alpha_path, fps=fps,
                options=encode_opts, on_progress=_progress,
            )
            total_size = rgb_result.file_size + alpha_result.file_size
            print(f"\r  atlas_{atlas.index}: 完成 (RGB {rgb_result.file_size/1024:.1f}KB + "
                  f"Alpha {alpha_result.file_size/1024:.1f}KB = {total_size/1024:.1f}KB, "
                  f"{rgb_result.frame_count}帧, {rgb_result.duration_seconds:.2f}s)")
        else:
            # 单轨编码: RGBA 视频 (yuva420p)
            video_path = str(Path(output_dir) / f"atlas_{atlas.index:03d}.webm")

            atlas.video_file = f"atlas_{atlas.index:03d}.webm"
            atlas.encode_options = encode_opts

            def _progress(p: float) -> None:
                pct = int(p * 100)
                print(f"\r  atlas_{atlas.index}: {pct}%", end="", flush=True)

            result = encoder.encode(
                frames_dir, video_path, fps=fps,
                options=encode_opts, on_progress=_progress,
            )
            print(f"\r  atlas_{atlas.index}: 完成 ({result.file_size / 1024:.1f} KB, "
                  f"{result.frame_count}帧, {result.duration_seconds:.2f}s)")

        # 清理临时帧目录
        shutil.rmtree(frames_dir, ignore_errors=True)

    # 重新保存元数据
    metadata.save(str(Path(output_dir) / "avap_metadata.json"))
    mode_str = "双轨(灰阶)" if dual_track else "单轨(yuva420p)"
    print(f"\n打包完成 [{mode_str}]: {output_dir}")


def cmd_decode(args: argparse.Namespace) -> None:
    """解码指定动画"""
    decoder = AVAPDecoder(args.metadata_json)
    names = args.animation_names

    try:
        decoder.decode_batch(names, output_dir=args.output)
    except KeyError as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_list(args: argparse.Namespace) -> None:
    """列出所有可用动画"""
    decoder = AVAPDecoder(args.metadata_json)
    names = decoder.list_animations()

    if not names:
        print("无可用动画")
        return

    print(f"可用动画 ({len(names)}):\n")
    for n in names:
        info, _ = decoder.find_animation(n)
        print(f"  {n:30s}  {info.frame_count:4d}帧  "
              f"{info.fps:.1f}fps  atlas#{info.atlas_index}")


def cmd_info(_args: argparse.Namespace) -> None:
    """打印工具链版本和依赖信息"""
    print(f"AVAP Toolchain v{avap.__version__}")
    print()

    deps = [
        ("ffmpeg", shutil.which("ffmpeg") or "未找到"),
        ("ffprobe", shutil.which("ffprobe") or "未找到"),
    ]

    try:
        from PIL import Image
        deps.append(("Pillow", Image.__version__))
    except ImportError:
        deps.append(("Pillow", "未安装"))

    print("依赖:")
    for name, val in deps:
        print(f"  {name:12s} {val}")


# ── 参数解析 ────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="avap",
        description="AVAP 动画视频资产包工具链",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # scan
    p_scan = sub.add_parser("scan", help="扫描素材目录")
    p_scan.add_argument("input_dir", help="素材目录路径")
    p_scan.set_defaults(func=cmd_scan)

    # pack
    p_pack = sub.add_parser("pack", help="完整打包流程")
    p_pack.add_argument("input_dir", help="素材目录路径")
    p_pack.add_argument("output_dir", nargs="?", default=None, help="输出目录 (默认: <input>/avap_output)")
    p_pack.add_argument("--atlas-size", type=int, default=2048, help="Atlas 画布尺寸 (默认: 2048)")
    p_pack.add_argument("--fps", type=float, default=30, help="输出帧率 (默认: 30)")
    p_pack.add_argument("--crf", type=int, default=25, help="VP9 CRF 值 (默认: 25, 越小质量越高)")
    p_pack.add_argument("--speed", type=int, default=0, help="VP9 编码速度 0-8 (默认: 0=最慢最高质量)")
    p_pack.add_argument("--threads", type=int, default=4, help="编码线程数 (默认: 4)")
    p_pack.add_argument("--dual-track", action="store_true", help="使用灰阶双轨编码 (RGB + Alpha 分离)")
    p_pack.set_defaults(func=cmd_pack)

    # decode
    p_decode = sub.add_parser("decode", help="解码指定动画")
    p_decode.add_argument("metadata_json", help="元数据 JSON 文件路径")
    p_decode.add_argument("animation_names", nargs="+", help="动画名称 (可指定多个)")
    p_decode.add_argument("-o", "--output", default=None, help="输出目录")
    p_decode.set_defaults(func=cmd_decode)

    # list
    p_list = sub.add_parser("list", help="列出所有可用动画")
    p_list.add_argument("metadata_json", help="元数据 JSON 文件路径")
    p_list.set_defaults(func=cmd_list)

    # info
    p_info = sub.add_parser("info", help="打印工具链版本和依赖信息")
    p_info.set_defaults(func=cmd_info)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
