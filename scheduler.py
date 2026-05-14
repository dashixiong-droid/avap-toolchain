"""
AVAP 打包调度器 - 核心调度逻辑
将多个动画素材动态装箱到 atlas 画布，逐帧合成 PNG 序列
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from PIL import Image
import numpy as np

from binpack import BinpackAtlas
from metadata_schema import AnimationInfo, AtlasMeta, AVAPMetadata
from scanner import AnimationAsset


@dataclass
class ActiveAnim:
    """画布上活跃的动画状态"""
    name: str
    rect_x: int
    rect_y: int
    rect_w: int                  # atlas 占位宽度（偶数对齐后）
    rect_h: int                  # atlas 占位高度（偶数对齐后）
    orig_w: int                  # 原始宽度
    orig_h: int                  # 原始高度
    frames_rendered: int = 0
    total_frames: int = 0
    start_frame: int = 0
    asset: AnimationAsset | None = None

    @property
    def finished(self) -> bool:
        return self.frames_rendered >= self.total_frames


class PackScheduler:
    """
    打包调度器：将动画素材动态装箱到 atlas，逐帧渲染输出

    核心流程:
    1. 初始化 BinpackAtlas 画布
    2. best_fit 选出最适合当前空闲区域的动画
    3. insert 到画布，记录位置和帧区间
    4. 逐帧渲染：合成所有活跃动画的当前帧
    5. 动画播完后 remove 腾出空间，再 best_fit 填入新动画
    6. 画布满后开新 atlas，直到全部打包完成
    """

    def __init__(self, atlas_width: int = 2048, atlas_height: int = 2048, fps: float = 30,
                 dual_track: bool = False):
        self.atlas_width = atlas_width
        self.atlas_height = atlas_height
        self.fps = fps
        self.dual_track = dual_track

    def pack(self, assets: List[AnimationAsset], output_dir: str) -> AVAPMetadata:
        """
        打包动画素材，输出 atlas PNG 序列和元数据

        Args:
            assets: 待打包的动画素材列表
            output_dir: 输出目录

        Returns:
            AVAPMetadata: 完整的打包元数据
        """
        out = Path(output_dir)
        out.mkdir(parents=True, exist_ok=True)

        metadata = AVAPMetadata()
        remaining = list(assets)

        atlas_index = 0
        while remaining:
            atlas_meta, remaining = self._pack_atlas(remaining, atlas_index, out)
            if atlas_meta is None:
                break  # 无法放入任何动画
            metadata.atlases.append(atlas_meta)
            atlas_index += 1

        # 保存元数据
        metadata.save(str(out / "avap_metadata.json"))
        return metadata

    def _pack_atlas(
        self, assets: List[AnimationAsset], atlas_index: int, output_dir: Path
    ) -> tuple[Optional[AtlasMeta], List[AnimationAsset]]:
        """
        打包单个 atlas：装箱 + 逐帧渲染

        Returns:
            (AtlasMeta 或 None, 剩余未打包的素材列表)
        """
        canvas = BinpackAtlas(self.atlas_width, self.atlas_height)
        active: dict[str, ActiveAnim] = {}
        packed: dict[str, ActiveAnim] = {}  # 已完成的动画记录

        # 候选池: name -> asset
        pool: dict[str, AnimationAsset] = {a.name: a for a in assets}
        remaining = list(assets)

        # 尝试填入初始动画
        self._fill_canvas(canvas, pool, active, 0)

        if not active:
            # 画布连一个动画都放不下
            return None, remaining

        # 逐帧渲染
        frame_dir = output_dir / f"atlas_{atlas_index:03d}"
        frame_dir.mkdir(parents=True, exist_ok=True)

        # 双轨模式: 创建 rgb 和 alpha 子目录
        if self.dual_track:
            rgb_dir = frame_dir / "rgb"
            alpha_dir = frame_dir / "alpha"
            rgb_dir.mkdir(parents=True, exist_ok=True)
            alpha_dir.mkdir(parents=True, exist_ok=True)

        global_frame = 0
        while active:
            # 渲染当前帧
            self._render_frame(active, global_frame, frame_dir, atlas_index)

            # 推进帧计数，移除已完成的动画
            finished_names = []
            for name, anim in active.items():
                anim.frames_rendered += 1
                if anim.finished:
                    finished_names.append(name)

            for name in finished_names:
                anim = active.pop(name)
                canvas.remove(name)
                packed[name] = anim

            # 腾出空间后尝试填入新动画
            if finished_names:
                self._fill_canvas(canvas, pool, active, global_frame + 1)

            global_frame += 1

        # 构建 AtlasMeta
        atlas_meta = AtlasMeta(
            index=atlas_index,
            video_file=f"atlas_{atlas_index:03d}.webm",
            width=self.atlas_width,
            height=self.atlas_height,
            fps=self.fps,
            total_frames=global_frame,
            alpha_video_file=f"atlas_{atlas_index:03d}_alpha.webm" if self.dual_track else "",
        )

        for name, anim in packed.items():
            atlas_meta.animations[name] = AnimationInfo(
                name=name,
                atlas_index=atlas_index,
                start_frame=anim.start_frame,
                end_frame=anim.start_frame + anim.total_frames - 1,
                rect_x=anim.rect_x,
                rect_y=anim.rect_y,
                rect_w=anim.rect_w,
                rect_h=anim.rect_h,
                orig_w=anim.orig_w,
                orig_h=anim.orig_h,
                frame_count=anim.total_frames,
                fps=anim.asset.fps if anim.asset else self.fps,
                original_name=anim.asset.dir_path if anim.asset else name,
            )

        # 计算剩余未打包的素材
        remaining = [a for a in assets if a.name not in packed]
        return atlas_meta, remaining

    def _fill_canvas(
        self,
        canvas: BinpackAtlas,
        pool: dict[str, AnimationAsset],
        active: dict[str, ActiveAnim],
        start_frame: int,
    ) -> None:
        """循环 best_fit + insert，尽可能填满画布"""
        while pool:
            candidates = [
                (name, asset.width, asset.height)
                for name, asset in pool.items()
                if name not in active
            ]
            if not candidates:
                break

            best = canvas.best_fit(candidates)
            if best is None:
                break

            name, w, h = best
            pos = canvas.insert(w, h, name)
            if pos is None:
                break

            asset = pool.pop(name)
            anim = ActiveAnim(
                name=name,
                rect_x=pos[0],
                rect_y=pos[1],
                rect_w=w,
                rect_h=h,
                orig_w=asset.width,
                orig_h=asset.height,
                total_frames=asset.frame_count,
                start_frame=start_frame,
                asset=asset,
            )
            active[name] = anim

    def _render_frame(
        self,
        active: dict[str, ActiveAnim],
        frame_idx: int,
        frame_dir: Path,
        atlas_index: int,
    ) -> None:
        """合成一帧 atlas 图像并保存为 PNG（双轨模式输出 RGB + Alpha 两张）"""
        img = Image.new("RGBA", (self.atlas_width, self.atlas_height), (0, 0, 0, 0))
        img_arr = np.array(img)  # 用 numpy 直接写入像素，避免 paste 的 alpha compositing

        for name, anim in active.items():
            frame_path = anim.asset.frames[anim.frames_rendered]
            try:
                frame_img = Image.open(frame_path).convert("RGBA")
                # 原始帧贴到偶数对齐的 rect 中，多余边留透明
                if frame_img.size != (anim.rect_w, anim.rect_h):
                    canvas_patch = Image.new("RGBA", (anim.rect_w, anim.rect_h), (0, 0, 0, 0))
                    canvas_patch.paste(frame_img, (0, 0), frame_img)
                    frame_img.close()
                    frame_img = canvas_patch
                # 直接写入像素，不做 alpha compositing（保留 straight alpha）
                frame_arr = np.array(frame_img)
                img_arr[anim.rect_y:anim.rect_y+anim.rect_h,
                        anim.rect_x:anim.rect_x+anim.rect_w] = frame_arr
                frame_img.close()
            except Exception as e:
                print(f"[WARN] 无法加载帧 {frame_path}: {e}")

        img = Image.fromarray(img_arr)

        idx_str = f"{frame_idx + 1:06d}"

        if self.dual_track:
            # 双轨模式: 输出 RGB（straight alpha，透明区域填黑但RGB不乘alpha）和 Alpha 灰度图
            # 注意: 必须用 straight alpha，否则解码合并后亮度会暗（premultiplied问题）
            r, g, b, a = img.split()
            # RGB 轨: 原始 RGB 值，透明区域填黑（A=0 的像素 RGB 也为 0）
            # 但半透明像素保留原始 RGB，不乘 alpha
            rgb_img = Image.merge("RGB", (r, g, b))
            alpha_img = a  # Alpha 轨: 灰度图

            rgb_dir = frame_dir / "rgb"
            alpha_dir = frame_dir / "alpha"
            rgb_img.save(str(rgb_dir / f"{idx_str}.png"), "PNG")
            alpha_img.save(str(alpha_dir / f"{idx_str}.png"), "PNG")
            rgb_img.close()
            alpha_img.close()
        else:
            # 单轨模式: 输出完整 RGBA PNG
            filename = f"{idx_str}.png"
            img.save(str(frame_dir / filename), "PNG")

        img.close()
