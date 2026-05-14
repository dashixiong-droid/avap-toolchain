"""
AVAP 视频编码模块
将 PNG 帧序列编码为 WebM，使用 EncodeOptions 控制参数
"""
from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from metadata_schema import EncodeOptions


@dataclass
class EncodeResult:
    """编码结果"""
    output_path: str
    file_size: int
    frame_count: int
    duration_seconds: float


class VideoEncoder:
    """
    视频编码器：将 PNG 帧序列编码为 WebM

    使用 FFmpeg 子进程，通过 EncodeOptions 控制编码参数。
    """

    def __init__(self, ffmpeg_path: str = "ffmpeg"):
        self.ffmpeg_path = ffmpeg_path

    def encode(
        self,
        frames_dir: str,
        output_path: str,
        fps: float = 30.0,
        options: Optional[EncodeOptions] = None,
        on_progress: Optional[Callable[[float], None]] = None,
    ) -> EncodeResult:
        """
        将帧序列目录编码为视频

        Args:
            frames_dir:   PNG 帧序列目录（000001.png, 000002.png, ...）
            output_path:  输出文件路径
            fps:          帧率
            options:      编码参数，默认 EncodeOptions()
            on_progress:  进度回调，参数为 0.0~1.0

        Returns:
            EncodeResult
        """
        if options is None:
            options = EncodeOptions()

        frames_path = Path(frames_dir)
        if not frames_path.is_dir():
            raise FileNotFoundError(f"帧目录不存在: {frames_dir}")

        # 统计帧数
        frame_files = sorted(
            f for f in frames_path.iterdir()
            if f.is_file() and re.match(r"\d+\.png$", f.name, re.IGNORECASE)
        )
        if not frame_files:
            raise FileNotFoundError(f"帧目录中无 PNG 帧文件: {frames_dir}")

        frame_count = len(frame_files)

        # 确保输出目录存在
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)

        # 构建 FFmpeg 命令
        input_pattern = str(frames_path / "%06d.png")
        cmd = [
            self.ffmpeg_path,
            "-y",
            "-framerate", str(fps),
            "-i", input_pattern,
        ] + options.to_ffmpeg_args() + [
            "-loglevel", "error",
            "-stats",
            str(out),
        ]

        # 启动 FFmpeg 子进程
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )

        # 读取 stderr：解析进度 + 收集错误信息
        stderr_lines: list[str] = []
        frame_re = re.compile(r"frame=\s*(\d+)")
        while True:
            line = proc.stderr.readline()
            if not line:
                break
            stderr_lines.append(line)
            if on_progress:
                m = frame_re.search(line)
                if m:
                    current = int(m.group(1))
                    progress = min(current / frame_count, 1.0) if frame_count > 0 else 0.0
                    on_progress(progress)

        proc.wait()
        stderr = "".join(stderr_lines)

        if proc.returncode != 0:
            raise RuntimeError(
                f"FFmpeg 编码失败 (exit={proc.returncode}):\n{stderr.strip()}"
            )

        # 验证输出文件
        if not out.exists() or out.stat().st_size == 0:
            raise RuntimeError(f"编码输出文件无效: {output_path}")

        file_size = out.stat().st_size
        duration_seconds = frame_count / fps if fps > 0 else 0.0

        return EncodeResult(
            output_path=str(out),
            file_size=file_size,
            frame_count=frame_count,
            duration_seconds=duration_seconds,
        )

    def encode_dual(
        self,
        frames_dir: str,
        output_rgb_path: str,
        output_alpha_path: str,
        fps: float = 30.0,
        options: Optional[EncodeOptions] = None,
        on_progress: Optional[Callable[[float], None]] = None,
    ) -> tuple[EncodeResult, EncodeResult]:
        """
        双轨编码: 将帧序列目录分别编码为 RGB 视频和 Alpha 灰度视频

        frames_dir 下应有 rgb/ 和 alpha/ 子目录，各含 PNG 帧序列。

        Args:
            frames_dir:        帧序列根目录（含 rgb/ 和 alpha/ 子目录）
            output_rgb_path:   RGB 视频输出路径
            output_alpha_path: Alpha 灰度视频输出路径
            fps:               帧率
            options:           编码参数，默认 EncodeOptions()
            on_progress:       进度回调（0.0~1.0，基于两轨总进度）

        Returns:
            (rgb_result, alpha_result)
        """
        if options is None:
            options = EncodeOptions()

        root = Path(frames_dir)
        rgb_dir = root / "rgb"
        alpha_dir = root / "alpha"

        if not rgb_dir.is_dir() or not alpha_dir.is_dir():
            raise FileNotFoundError(
                f"双轨模式需要 {root}/rgb/ 和 {root}/alpha/ 子目录"
            )

        # 构建双轨专用的编码参数: yuv420p（无 alpha 通道）
        rgb_opts = EncodeOptions(
            codec=options.codec,
            pix_fmt="yuv420p",
            crf=options.crf,
            speed=options.speed,
            row_mt=options.row_mt,
            threads=options.threads,
            gop_size=options.gop_size,
            extra_args=list(options.extra_args),
        )

        alpha_opts = EncodeOptions(
            codec=options.codec,
            pix_fmt="yuv420p",
            crf=options.crf,
            speed=options.speed,
            row_mt=options.row_mt,
            threads=options.threads,
            gop_size=options.gop_size,
            extra_args=list(options.extra_args),
        )

        # 进度分两阶段: RGB 0~0.5, Alpha 0.5~1.0
        def _rgb_progress(p: float) -> None:
            if on_progress:
                on_progress(p * 0.5)

        def _alpha_progress(p: float) -> None:
            if on_progress:
                on_progress(0.5 + p * 0.5)

        rgb_result = self.encode(
            str(rgb_dir), output_rgb_path, fps=fps,
            options=rgb_opts, on_progress=_rgb_progress,
        )
        alpha_result = self.encode(
            str(alpha_dir), output_alpha_path, fps=fps,
            options=alpha_opts, on_progress=_alpha_progress,
        )

        return rgb_result, alpha_result