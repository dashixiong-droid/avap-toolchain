"""
AVAP 元数据结构定义
"""
from dataclasses import dataclass, field
from typing import Optional
import json


@dataclass
class EncodeOptions:
    """视频编码参数"""
    codec: str = "libvpx-vp9"
    pix_fmt: str = "yuva420p"
    crf: int = 25
    speed: int = 0          # VP9 -cpu-used (0=最慢最高质量, 8=最快)
    row_mt: int = 1         # 行级多线程
    threads: int = 4        # 编码线程数
    gop_size: int = 0       # 关键帧间隔 (0=自动, 1=全关键帧)
    extra_args: list[str] = field(default_factory=list)  # 额外 FFmpeg 参数

    def to_dict(self) -> dict:
        d = {
            "codec": self.codec,
            "pix_fmt": self.pix_fmt,
            "crf": self.crf,
            "speed": self.speed,
            "row_mt": self.row_mt,
            "threads": self.threads,
        }
        if self.gop_size > 0:
            d["gop_size"] = self.gop_size
        if self.extra_args:
            d["extra_args"] = self.extra_args
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "EncodeOptions":
        return cls(
            codec=d.get("codec", "libvpx-vp9"),
            pix_fmt=d.get("pix_fmt", "yuva420p"),
            crf=d.get("crf", 25),
            speed=d.get("speed", 0),
            row_mt=d.get("row_mt", 1),
            threads=d.get("threads", 4),
            gop_size=d.get("gop_size", 0),
            extra_args=d.get("extra_args", []),
        )

    def to_ffmpeg_args(self) -> list[str]:
        """转换为 FFmpeg 编码参数列表"""
        args = [
            "-c:v", self.codec,
            "-pix_fmt", self.pix_fmt,
            "-crf", str(self.crf),
            "-b:v", "0",
            "-cpu-used", str(self.speed),
            "-row-mt", str(self.row_mt),
            "-threads", str(self.threads),
        ]
        # VP9 alpha 兼容性
        if self.pix_fmt == "yuva420p":
            args.extend(["-auto-alt-ref", "0"])
        if self.gop_size > 0:
            args.extend(["-g", str(self.gop_size)])
        args.extend(self.extra_args)
        return args


@dataclass
class AnimationInfo:
    """单个动画在 atlas 中的位置信息"""
    name: str                    # 动画名称
    atlas_index: int             # 所属 atlas 编号
    start_frame: int             # 在视频中的起始帧（全局帧索引）
    end_frame: int               # 在视频中的结束帧（含）
    rect_x: int                  # 在 atlas 帧中的 x 偏移
    rect_y: int                  # 在 atlas 帧中的 y 偏移
    rect_w: int                  # atlas 中占位宽度（偶数对齐后）
    rect_h: int                  # atlas 中占位高度（偶数对齐后）
    orig_w: int                  # 动画原始宽度
    orig_h: int                  # 动画原始高度
    frame_count: int             # 总帧数
    fps: float                   # 原始帧率
    original_name: str = ""      # 原始目录名

    def to_dict(self) -> dict:
        return {
            "atlas_index": self.atlas_index,
            "start_frame": self.start_frame,
            "end_frame": self.end_frame,
            "rect": {
                "x": self.rect_x,
                "y": self.rect_y,
                "w": self.rect_w,
                "h": self.rect_h,
            },
            "orig_size": {
                "w": self.orig_w,
                "h": self.orig_h,
            },
            "frame_count": self.frame_count,
            "fps": self.fps,
            "original_name": self.original_name or self.name,
        }


@dataclass
class AtlasMeta:
    """单个 atlas 视频的元数据"""
    index: int
    video_file: str
    width: int
    height: int
    fps: float
    total_frames: int
    encode_options: EncodeOptions = field(default_factory=EncodeOptions)
    animations: dict[str, AnimationInfo] = field(default_factory=dict)
    alpha_video_file: str = ""  # 双轨模式下的 alpha 灰度视频文件名

    def to_dict(self) -> dict:
        d = {
            "index": self.index,
            "video_file": self.video_file,
            "width": self.width,
            "height": self.height,
            "fps": self.fps,
            "total_frames": self.total_frames,
            "encode_options": self.encode_options.to_dict(),
            "animations": {
                name: info.to_dict() for name, info in self.animations.items()
            },
        }
        if self.alpha_video_file:
            d["alpha_video_file"] = self.alpha_video_file
        return d


@dataclass
class AVAPMetadata:
    """整个 AVAP 包的元数据"""
    version: int = 1
    atlases: list[AtlasMeta] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "version": self.version,
            "atlases": [a.to_dict() for a in self.atlases],
        }

    def save(self, path: str):
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2, ensure_ascii=False)

    @classmethod
    def load(cls, path: str) -> "AVAPMetadata":
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        meta = cls(version=data["version"])
        for ad in data["atlases"]:
            atlas = AtlasMeta(
                index=ad["index"],
                video_file=ad["video_file"],
                width=ad["width"],
                height=ad["height"],
                fps=ad["fps"],
                total_frames=ad["total_frames"],
                encode_options=EncodeOptions.from_dict(ad.get("encode_options", {})),
                alpha_video_file=ad.get("alpha_video_file", ""),
            )
            for name, info in ad["animations"].items():
                r = info["rect"]
                os_ = info.get("orig_size", {"w": r["w"], "h": r["h"]})
                atlas.animations[name] = AnimationInfo(
                    name=name,
                    atlas_index=atlas.index,
                    start_frame=info["start_frame"],
                    end_frame=info["end_frame"],
                    rect_x=r["x"],
                    rect_y=r["y"],
                    rect_w=r["w"],
                    rect_h=r["h"],
                    orig_w=os_["w"],
                    orig_h=os_["h"],
                    frame_count=info["frame_count"],
                    fps=info["fps"],
                    original_name=info.get("original_name", name),
                )
            meta.atlases.append(atlas)
        return meta
