"""
AVAP 素材扫描模块
扫描目录下的 RGBA PNG 序列帧动画素材
"""
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

# 帧文件匹配: 0001.png, frame_0001.png, 001.png 等
_FRAME_RE = re.compile(r".*?(\d+)\.png$", re.IGNORECASE)

# 目录名后缀解析: name@60fps, name@24fps
_FPS_SUFFIX_RE = re.compile(r"^(.+)@(\d+(?:\.\d+)?)fps$", re.IGNORECASE)

DEFAULT_FPS = 30.0


@dataclass
class AnimationAsset:
    """扫描得到的单个动画素材"""
    name: str                         # 动画名称（去除@fps后缀）
    dir_path: str                     # 帧文件所在目录
    frame_count: int                  # 帧数
    width: int                        # 帧宽度
    height: int                       # 帧高度
    fps: float                        # 帧率
    frames: List[str] = field(default_factory=list)  # 帧文件路径列表（有序）


def _parse_fps_from_dirname(dirname: str) -> tuple[str, float]:
    """从目录名解析名称和帧率，如 effect_a@60fps -> ('effect_a', 60.0)"""
    m = _FPS_SUFFIX_RE.match(dirname)
    if m:
        return m.group(1).strip(), float(m.group(2))
    return dirname, DEFAULT_FPS


def _is_frame_file(filename: str) -> bool:
    """判断是否为帧 PNG 文件"""
    return bool(_FRAME_RE.match(filename))


def _read_png_size(path: str) -> Optional[tuple[int, int]]:
    """读取 PNG 文件尺寸（解析 IHDR chunk，无需第三方库）"""
    try:
        with open(path, "rb") as f:
            header = f.read(24)
            if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
                return None
            # IHDR: width(4) + height(4) at offset 16
            w = int.from_bytes(header[16:20], "big")
            h = int.from_bytes(header[20:24], "big")
            return w, h
    except (OSError, ValueError):
        return None


def _scan_single_dir(dir_path: str) -> Optional[AnimationAsset]:
    """扫描单个目录，返回 AnimationAsset 或 None（无帧文件时）"""
    p = Path(dir_path)
    if not p.is_dir():
        return None

    # 收集帧文件
    frame_files: list[str] = []
    for entry in sorted(p.iterdir()):
        if entry.is_file() and _is_frame_file(entry.name):
            frame_files.append(str(entry))

    if not frame_files:
        return None

    # 解析名称和帧率
    name, fps = _parse_fps_from_dirname(p.name)

    # 读取第一帧尺寸
    size = _read_png_size(frame_files[0])
    if size is None:
        return None
    width, height = size

    return AnimationAsset(
        name=name,
        dir_path=str(p),
        frame_count=len(frame_files),
        width=width,
        height=height,
        fps=fps,
        frames=frame_files,
    )


class AssetScanner:
    """素材扫描器"""

    def scan(self, root_dir: str, recursive: bool = True) -> List[AnimationAsset]:
        """
        扫描指定目录下的所有动画素材

        每个包含 PNG 序列帧的子目录视为一个动画。
        recursive=True 时递归扫描所有层级子目录。
        """
        root = Path(root_dir)
        if not root.is_dir():
            raise FileNotFoundError(f"目录不存在: {root_dir}")

        assets: List[AnimationAsset] = []
        self._walk(root, recursive, assets)
        return assets

    def _walk(self, dir_path: Path, recursive: bool, out: List[AnimationAsset]):
        """遍历目录，收集动画素材"""
        # 先检查当前目录是否直接包含帧文件
        asset = _scan_single_dir(str(dir_path))
        if asset is not None:
            out.append(asset)
            return  # 帧目录不再向下递归（帧目录内不应有子动画）

        # 当前目录不是帧目录，遍历子目录
        try:
            entries = sorted(dir_path.iterdir())
        except PermissionError:
            return

        for entry in entries:
            if not entry.is_dir():
                continue
            if recursive:
                self._walk(entry, recursive, out)
            else:
                asset = _scan_single_dir(str(entry))
                if asset is not None:
                    out.append(asset)
