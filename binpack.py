"""
AVAP Binpack - 动态矩形装箱算法
支持插入、移除、空闲区域合并、最佳匹配筛选

基于 MaxRects 算法，移除时合并相邻空闲区域
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Rect:
    x: int
    y: int
    w: int
    h: int

    @property
    def area(self) -> int:
        return self.w * self.h

    @property
    def right(self) -> int:
        return self.x + self.w

    @property
    def bottom(self) -> int:
        return self.y + self.h

    def contains(self, other: Rect) -> bool:
        return (other.x >= self.x and other.y >= self.y and
                other.right <= self.right and other.bottom <= self.bottom)

    def intersects(self, other: Rect) -> bool:
        return not (other.right <= self.x or other.x >= self.right or
                    other.bottom <= self.y or other.y >= self.bottom)

    def overlap_area(self, other: Rect) -> int:
        if not self.intersects(other):
            return 0
        x1 = max(self.x, other.x)
        y1 = max(self.y, other.y)
        x2 = min(self.right, other.right)
        y2 = min(self.bottom, other.bottom)
        return (x2 - x1) * (y2 - y1)


class BinpackAtlas:
    """
    动态矩形装箱器
    - insert: 放入一个矩形，返回位置或 None
    - remove: 移除一个矩形，释放空间并合并空闲区域
    - best_fit: 从候选列表中选出最适合当前空闲区域的矩形
    """

    def __init__(self, width: int, height: int, even_align: bool = True):
        self.width = width
        self.height = height
        self.even_align = even_align
        # 空闲矩形列表
        self._free: list[Rect] = [Rect(0, 0, width, height)]
        # 已放置的矩形: name -> Rect
        self._used: dict[str, Rect] = {}

    @staticmethod
    def _to_even(v: int) -> int:
        """向上取偶数: 奇数+1, 偶数不变"""
        return v if v % 2 == 0 else v + 1

    def insert(self, w: int, h: int, name: str) -> Optional[tuple[int, int]]:
        """
        尝试放入一个 w×h 的矩形，返回 (x, y) 或 None
        使用 Best Short Side Fit (BSSF) 策略
        
        even_align=True 时: w/h 向上取偶数，放置位置 x/y 也偶数对齐
        """
        if name in self._used:
            raise ValueError(f"Name '{name}' already placed")

        # 偶数对齐
        if self.even_align:
            w = self._to_even(w)
            h = self._to_even(h)

        best_rect = None
        best_pos = None
        best_short = float('inf')
        best_long = float('inf')

        for free in self._free:
            # 偶数对齐时，位置也必须是偶数
            px = free.x
            py = free.y
            if self.even_align:
                px = self._to_even(px)
                py = self._to_even(py)
                # 对齐后可能超出 free 区域，需要重新检查
                if px + w > free.right or py + h > free.bottom:
                    continue
            if w <= free.w and h <= free.h and px + w <= free.right and py + h <= free.bottom:
                short = min(free.right - (px + w), free.bottom - (py + h))
                long = max(free.right - (px + w), free.bottom - (py + h))
                if short < best_short or (short == best_short and long < best_long):
                    best_short = short
                    best_long = long
                    best_rect = free
                    best_pos = (px, py)

        if best_pos is None:
            return None

        placed = Rect(best_pos[0], best_pos[1], w, h)
        self._used[name] = placed

        # 从空闲列表中分割
        new_free: list[Rect] = []
        for free in self._free:
            if not free.intersects(placed):
                new_free.append(free)
                continue
            # 分割: 将 free 中与 placed 不重叠的部分加入
            # 上方
            if placed.y > free.y:
                new_free.append(Rect(free.x, free.y, free.w, placed.y - free.y))
            # 下方
            if placed.bottom < free.bottom:
                new_free.append(Rect(free.x, placed.bottom, free.w, free.bottom - placed.bottom))
            # 左方
            if placed.x > free.x:
                new_free.append(Rect(free.x, free.y, placed.x - free.x, free.h))
            # 右方
            if placed.right < free.right:
                new_free.append(Rect(placed.right, free.y, free.right - placed.right, free.h))

        self._free = self._prune_free(new_free)
        return best_pos

    def remove(self, name: str) -> bool:
        """
        移除已放置的矩形，释放空间并合并相邻空闲区域
        """
        if name not in self._used:
            return False

        rect = self._used.pop(name)
        self._free.append(rect)
        self._free = self._merge_free(self._free)
        return True

    def get_free_rects(self) -> list[tuple[int, int, int, int]]:
        """返回空闲矩形列表 (x, y, w, h)"""
        return [(r.x, r.y, r.w, r.h) for r in self._free]

    def best_fit(self, candidates: list[tuple[str, int, int]]) -> Optional[tuple[str, int, int]]:
        """
        从候选动画中选出最适合当前空闲区域的
        candidates: [(name, width, height), ...]
        返回: (name, width, height) 或 None
        
        策略: 找到能放入某个空闲矩形、且面积利用率最高的候选
        利用率 = 候选面积 / 空闲矩形面积，越接近1越好
        """
        best_candidate = None
        best_score = -1  # 利用率

        for name, cw, ch in candidates:
            # 找能放下这个候选的最小空闲矩形
            for free in self._free:
                if cw <= free.w and ch <= free.h:
                    utilization = (cw * ch) / free.area
                    if utilization > best_score:
                        best_score = utilization
                        best_candidate = (name, cw, ch)
                    break  # 找到一个能放的空闲区域就够了

        return best_candidate

    def can_fit(self, w: int, h: int) -> bool:
        """检查是否能放入指定尺寸的矩形"""
        return any(f.w >= w and f.h >= h for f in self._free)

    def occupancy(self) -> float:
        """当前利用率 (0.0 ~ 1.0)"""
        used_area = sum(r.area for r in self._used.values())
        return used_area / (self.width * self.height)

    @property
    def used_names(self) -> list[str]:
        return list(self._used.keys())

    def _prune_free(self, rects: list[Rect]) -> list[Rect]:
        """移除被其他空闲矩形完全包含的矩形"""
        result: list[Rect] = []
        for i, r in enumerate(rects):
            contained = False
            for j, other in enumerate(rects):
                if i != j and other.contains(r):
                    contained = True
                    break
            if not contained:
                result.append(r)
        return result

    def _merge_free(self, rects: list[Rect]) -> list[Rect]:
        """合并相邻的空闲矩形"""
        # 先去包含
        rects = self._prune_free(rects)
        # 尝试水平合并
        merged = True
        while merged:
            merged = False
            new_rects: list[Rect] = []
            used = [False] * len(rects)
            for i in range(len(rects)):
                if used[i]:
                    continue
                for j in range(i + 1, len(rects)):
                    if used[j]:
                        continue
                    ri, rj = rects[i], rects[j]
                    # 水平相邻: 同y同h，左右相接
                    if ri.y == rj.y and ri.h == rj.h:
                        if ri.right == rj.x:
                            new_rects.append(Rect(ri.x, ri.y, ri.w + rj.w, ri.h))
                            used[i] = used[j] = True
                            merged = True
                            break
                        if rj.right == ri.x:
                            new_rects.append(Rect(rj.x, rj.y, ri.w + rj.w, ri.h))
                            used[i] = used[j] = True
                            merged = True
                            break
                    # 垂直相邻: 同x同w，上下相接
                    if ri.x == rj.x and ri.w == rj.w:
                        if ri.bottom == rj.y:
                            new_rects.append(Rect(ri.x, ri.y, ri.w, ri.h + rj.h))
                            used[i] = used[j] = True
                            merged = True
                            break
                        if rj.bottom == ri.y:
                            new_rects.append(Rect(rj.x, rj.y, ri.w, ri.h + rj.h))
                            used[i] = used[j] = True
                            merged = True
                            break
                if not used[i]:
                    new_rects.append(rects[i])
            rects = self._prune_free(new_rects)
        return rects
