"""
AVAP 运行时解码模块
根据元数据从 atlas 视频中解码指定动画的帧，输出为 PNG 序列
"""
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from metadata_schema import AVAPMetadata, AnimationInfo


class AVAPDecoder:
    """AVAP 解码器：从 atlas 视频中提取动画帧"""

    def __init__(self, metadata_path: str, ffmpeg_path: str = "ffmpeg"):
        self.metadata_path = Path(metadata_path)
        self.ffmpeg_path = ffmpeg_path
        self.metadata: AVAPMetadata = AVAPMetadata.load(str(self.metadata_path))
        self.base_dir: Path = self.metadata_path.parent

    # ── 查找 ──────────────────────────────────────────────

    def find_animation(self, name: str) -> tuple[AnimationInfo, str]:
        """查找动画，返回 (AnimationInfo, atlas视频绝对路径)"""
        for atlas in self.metadata.atlases:
            if name in atlas.animations:
                info = atlas.animations[name]
                video = str(self.base_dir / atlas.video_file)
                return info, video
        available = self.list_animations()
        raise KeyError(
            f"动画 '{name}' 未找到。可用动画: {', '.join(available)}"
        )

    def _is_dual_track(self, atlas_index: int) -> bool:
        """判断指定 atlas 是否为双轨模式"""
        for atlas in self.metadata.atlases:
            if atlas.index == atlas_index:
                return bool(atlas.alpha_video_file)
        return False

    def _find_alpha_video(self, atlas_index: int) -> str | None:
        """获取指定 atlas 的 alpha 视频绝对路径，单轨返回 None"""
        for atlas in self.metadata.atlases:
            if atlas.index == atlas_index and atlas.alpha_video_file:
                return str(self.base_dir / atlas.alpha_video_file)
        return None

    def list_animations(self) -> list[str]:
        """列出所有可用动画名称"""
        names: list[str] = []
        for atlas in self.metadata.atlases:
            names.extend(atlas.animations.keys())
        return names

    # ── 解码 ──────────────────────────────────────────────

    def decode(
        self,
        name: str,
        output_dir: str | None = None,
        info_only: bool = False,
    ) -> Path:
        """
        解码指定动画的帧序列

        Args:
            name:        动画名称
            output_dir:  输出目录，默认为 <base_dir>/decoded/<name>
            info_only:   仅打印帧数据信息，不输出 PNG

        Returns:
            输出目录 Path
        """
        info, video = self.find_animation(name)

        if info_only:
            self._print_info(name, info, video)
            return Path("")

        out = Path(output_dir) if output_dir else self.base_dir / "decoded" / name
        out.mkdir(parents=True, exist_ok=True)

        # 构建 FFmpeg 滤镜：选帧 + 裁切
        vf = (
            f"select=between(n\\,{info.start_frame}\\,{info.end_frame}),"
            f"crop={info.rect_w}:{info.rect_h}:{info.rect_x}:{info.rect_y}"
        )

        dual = self._is_dual_track(info.atlas_index)

        if dual:
            # 双轨解码: 分别解码 RGB 和 Alpha，再合并为 RGBA
            alpha_video = self._find_alpha_video(info.atlas_index)
            if not alpha_video:
                raise RuntimeError(
                    f"双轨模式但未找到 alpha 视频 (atlas={info.atlas_index})"
                )

            # 临时目录存放原始 RGB 和 Alpha 帧
            tmp_rgb = out / "_tmp_rgb"
            tmp_alpha = out / "_tmp_alpha"
            tmp_rgb.mkdir(parents=True, exist_ok=True)
            tmp_alpha.mkdir(parents=True, exist_ok=True)

            # 解码 RGB 视频
            cmd_rgb = [
                self.ffmpeg_path,
                "-i", video,
                "-vf", vf,
                "-vsync", "vfr",
                "-loglevel", "error",
                "-y",
                str(tmp_rgb / "%06d.png"),
            ]
            print(f"[decoder] 双轨解码 RGB '{name}' -> {tmp_rgb}")
            result = subprocess.run(cmd_rgb, capture_output=True, text=True)
            if result.returncode != 0:
                raise RuntimeError(
                    f"FFmpeg RGB 解码失败 (exit={result.returncode}):\n{result.stderr.strip()}"
                )

            # 解码 Alpha 灰度视频
            cmd_alpha = [
                self.ffmpeg_path,
                "-i", alpha_video,
                "-vf", vf,
                "-vsync", "vfr",
                "-loglevel", "error",
                "-y",
                str(tmp_alpha / "%06d.png"),
            ]
            print(f"[decoder] 双轨解码 Alpha '{name}' -> {tmp_alpha}")
            result = subprocess.run(cmd_alpha, capture_output=True, text=True)
            if result.returncode != 0:
                raise RuntimeError(
                    f"FFmpeg Alpha 解码失败 (exit={result.returncode}):\n{result.stderr.strip()}"
                )

            # 合并 RGB + Alpha → RGBA
            from PIL import Image

            rgb_frames = sorted(tmp_rgb.glob("*.png"))
            alpha_frames = sorted(tmp_alpha.glob("*.png"))

            if len(rgb_frames) != len(alpha_frames):
                print(f"[WARN] RGB帧数({len(rgb_frames)}) != Alpha帧数({len(alpha_frames)})")

            count = 0
            for i, (rgb_path, alpha_path) in enumerate(
                zip(rgb_frames, alpha_frames), start=1
            ):
                rgb_img = Image.open(rgb_path).convert("RGB")
                alpha_img = Image.open(alpha_path).convert("L")
                rgba_img = Image.merge("RGBA", (
                    rgb_img.split()[0],
                    rgb_img.split()[1],
                    rgb_img.split()[2],
                    alpha_img.split()[0],
                ))
                rgba_img.save(str(out / f"{i:06d}.png"), "PNG")
                rgb_img.close()
                alpha_img.close()
                rgba_img.close()
                count += 1

            # 清理临时目录
            import shutil
            shutil.rmtree(tmp_rgb, ignore_errors=True)
            shutil.rmtree(tmp_alpha, ignore_errors=True)

            print(f"  完成: {count} 帧 (双轨合并)")
            return out

        # 单轨解码: 直接解码 RGBA 视频
        output_pattern = str(out / "%06d.png")
        cmd = [
            self.ffmpeg_path,
            "-c:v", "libvpx-vp9",      # 必须用 libvpx 解码器才能正确还原 VP9 alpha
            "-i", video,
            "-vf", vf,
            "-vsync", "vfr",
            "-loglevel", "error",
            "-y",
            output_pattern,
        ]

        print(f"[decoder] 正在解码 '{name}' -> {out}")
        print(f"  atlas={info.atlas_index}  frames=[{info.start_frame}..{info.end_frame}]  "
              f"rect=({info.rect_x},{info.rect_y},{info.rect_w},{info.rect_h})")

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(
                f"FFmpeg 解码失败 (exit={result.returncode}):\n{result.stderr.strip()}"
            )

        count = len(list(out.glob("*.png")))
        print(f"  完成: {count} 帧")
        return out

    def decode_batch(
        self,
        names: list[str],
        output_dir: str | None = None,
    ) -> list[Path]:
        """批量解码多个动画，每个动画独立子目录"""
        results: list[Path] = []
        base = Path(output_dir) if output_dir else self.base_dir / "decoded"
        for name in names:
            sub_dir = str(base / name)
            results.append(self.decode(name, output_dir=sub_dir))
        return results

    # ── 信息打印 ──────────────────────────────────────────

    @staticmethod
    def _print_info(name: str, info: AnimationInfo, video: str) -> None:
        print(f"动画: {name}")
        print(f"  原始名称:  {info.original_name}")
        print(f"  Atlas:     {info.atlas_index}")
        print(f"  视频文件:  {video}")
        print(f"  帧区间:    [{info.start_frame} .. {info.end_frame}]")
        print(f"  帧数:      {info.frame_count}")
        print(f"  帧率:      {info.fps} fps")
        print(f"  裁切区域:  x={info.rect_x}  y={info.rect_y}  "
              f"w={info.rect_w}  h={info.rect_h}")


# ── CLI ────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="AVAP 运行时解码工具 — 从 atlas 视频中提取动画帧"
    )
    parser.add_argument(
        "animations", nargs="*",
        help="要解码的动画名称（可指定多个）",
    )
    parser.add_argument(
        "-m", "--metadata", default="avap_metadata.json",
        help="元数据文件路径 (默认: avap_metadata.json)",
    )
    parser.add_argument(
        "-o", "--output", default=None,
        help="输出目录 (默认: <metadata所在目录>/decoded/<动画名>)",
    )
    parser.add_argument(
        "--list", action="store_true",
        help="列出所有可用动画",
    )
    parser.add_argument(
        "--info", action="store_true",
        help="仅打印帧数据信息，不输出 PNG",
    )
    parser.add_argument(
        "--ffmpeg", default="ffmpeg",
        help="FFmpeg 可执行文件路径 (默认: ffmpeg)",
    )

    args = parser.parse_args()
    decoder = AVAPDecoder(args.metadata, ffmpeg_path=args.ffmpeg)

    if args.list:
        names = decoder.list_animations()
        if not names:
            print("无可用动画")
        else:
            print(f"可用动画 ({len(names)}):")
            for n in names:
                info, _ = decoder.find_animation(n)
                print(f"  {n:30s}  {info.frame_count:4d}帧  "
                      f"{info.fps:.1f}fps  atlas#{info.atlas_index}")
        return

    if not args.animations:
        parser.error("请指定动画名称，或使用 --list 查看可用动画")

    if args.info:
        for name in args.animations:
            info, video = decoder.find_animation(name)
            decoder._print_info(name, info, video)
            print()
    else:
        decoder.decode_batch(args.animations, output_dir=args.output)


if __name__ == "__main__":
    main()
