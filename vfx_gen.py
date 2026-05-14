"""
AVAP 测试素材生成器 - 程序化特效动画
生成多种典型游戏特效的 RGBA 帧序列，用于验证打包流程
"""
import math
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


def _lerp(a, b, t):
    return a + (b - a) * t


def _ease_out(t):
    return 1 - (1 - t) ** 2


def _ease_in_out(t):
    return 3 * t * t - 2 * t * t * t


def generate_explosion(out_dir: str, size: int = 256, frames: int = 30):
    """爆炸特效：中心扩散 + 颜色渐变 + 透明衰减"""
    d = Path(out_dir); d.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        t = i / (frames - 1)
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = size // 2, size // 2
        # 多层圆环
        for layer in range(4):
            lt = max(0, t - layer * 0.08)
            if lt <= 0: continue
            radius = int(size * 0.4 * _ease_out(lt) * (1 + layer * 0.3))
            alpha = int(255 * max(0, 1 - lt * 1.2) * (1 - layer * 0.2))
            if alpha <= 0: continue
            # 颜色: 白→黄→橙→红
            if lt < 0.3:
                r, g, b = 255, 255, int(_lerp(255, 180, lt / 0.3))
            elif lt < 0.6:
                r, g, b = 255, int(_lerp(180, 80, (lt - 0.3) / 0.3)), 0
            else:
                r, g, b = int(_lerp(255, 120, (lt - 0.6) / 0.4)), int(_lerp(80, 20, (lt - 0.6) / 0.4)), 0
            draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
                         fill=(r, g, b, alpha))
        # 火花粒子
        random.seed(42)
        for _ in range(20):
            angle = random.uniform(0, 2 * math.pi)
            speed = random.uniform(0.3, 1.0)
            dist = int(size * 0.35 * speed * _ease_out(t))
            px = cx + int(dist * math.cos(angle))
            py = cy + int(dist * math.sin(angle))
            pr = max(1, int(4 * (1 - t)))
            pa = int(200 * max(0, 1 - t * 1.5))
            if pa > 0 and 0 <= px < size and 0 <= py < size:
                draw.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(255, 220, 100, pa))
        img = img.filter(ImageFilter.GaussianBlur(radius=2))
        img.save(d / f"{i + 1:04d}.png")


def generate_aura_loop(out_dir: str, size: int = 256, frames: int = 40):
    """光环循环：旋转光环 + 脉冲"""
    d = Path(out_dir); d.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        t = i / frames
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = size // 2, size // 2
        pulse = 0.85 + 0.15 * math.sin(t * 2 * math.pi)
        # 外环
        for ring in range(3):
            radius = int(size * 0.35 * pulse * (0.8 + ring * 0.15))
            alpha = int(120 * (1 - ring * 0.3))
            angle_offset = t * 2 * math.pi + ring * 0.5
            # 弧段
            for seg in range(6):
                a1 = angle_offset + seg * math.pi / 3
                a2 = a1 + math.pi / 6
                bbox = [cx - radius, cy - radius, cx + radius, cy + radius]
                draw.arc(bbox, int(math.degrees(a1)), int(math.degrees(a2)),
                         fill=(100, 200, 255, alpha), width=3)
        # 中心光点
        cr = int(size * 0.08 * pulse)
        draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(150, 220, 255, 180))
        img = img.filter(ImageFilter.GaussianBlur(radius=1))
        img.save(d / f"{i + 1:04d}.png")


def generate_sparkle(out_dir: str, size: int = 64, frames: int = 12):
    """闪烁星星：十字光芒 + 缩放"""
    d = Path(out_dir); d.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        t = i / (frames - 1)
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = size // 2, size // 2
        scale = 1 - abs(2 * t - 1)  # 0→1→0
        length = int(size * 0.4 * scale)
        alpha = int(255 * scale)
        # 十字
        draw.line([(cx - length, cy), (cx + length, cy)], fill=(255, 255, 200, alpha), width=2)
        draw.line([(cx, cy - length), (cx, cy + length)], fill=(255, 255, 200, alpha), width=2)
        # 对角
        dl = int(length * 0.5)
        draw.line([(cx - dl, cy - dl), (cx + dl, cy + dl)], fill=(255, 255, 200, alpha // 2), width=1)
        draw.line([(cx - dl, cy + dl), (cx + dl, cy - dl)], fill=(255, 255, 200, alpha // 2), width=1)
        # 中心点
        if scale > 0.3:
            cr = max(1, int(3 * scale))
            draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(255, 255, 255, alpha))
        img.save(d / f"{i + 1:04d}.png")


def generate_fire_ring(out_dir: str, size: int = 192, frames: int = 24):
    """火环：环形火焰 + 上升火星"""
    d = Path(out_dir); d.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        t = i / frames
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = size // 2, size // 2
        radius = int(size * 0.3)
        # 环形火焰粒子
        random.seed(99)
        for _ in range(60):
            angle = random.uniform(0, 2 * math.pi)
            r_var = random.uniform(-8, 8)
            px = cx + int((radius + r_var) * math.cos(angle + t * math.pi))
            py = cy + int((radius + r_var) * math.sin(angle + t * math.pi))
            # 上升偏移
            py -= int(random.uniform(0, 15) * _ease_out(t))
            pr = random.randint(2, 5)
            alpha = int(180 * random.uniform(0.5, 1.0))
            r = random.randint(200, 255)
            g = random.randint(80, 180)
            b = random.randint(0, 40)
            draw.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(r, g, b, alpha))
        img = img.filter(ImageFilter.GaussianBlur(radius=2))
        img.save(d / f"{i + 1:04d}.png")


def generate_heal_effect(out_dir: str, size: int = 200, frames: int = 30):
    """治疗特效：上升光柱 + 十字 + 粒子"""
    d = Path(out_dir); d.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        t = i / (frames - 1)
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = size // 2, size // 2
        # 光柱（从下往上）
        rise = _ease_out(min(t * 1.5, 1.0))
        fade = max(0, 1 - (t - 0.6) / 0.4) if t > 0.6 else 1.0
        pw = int(size * 0.15 * rise)
        ph = int(size * 0.7 * rise)
        py_top = cy - ph // 2
        alpha = int(100 * fade)
        draw.rectangle([cx - pw, py_top, cx + pw, py_top + ph], fill=(100, 255, 150, alpha))
        # 十字
        if t > 0.2:
            ct = (t - 0.2) / 0.8
            cl = int(size * 0.25 * _ease_out(ct))
            ca = int(220 * fade)
            draw.line([(cx - cl, cy), (cx + cl, cy)], fill=(200, 255, 200, ca), width=3)
            draw.line([(cx, cy - cl), (cx, cy + cl)], fill=(200, 255, 200, ca), width=3)
        # 上升粒子
        random.seed(77)
        for _ in range(15):
            px = cx + random.randint(-pw, pw)
            base_py = cy + random.randint(0, ph // 2)
            py = base_py - int(ph * 0.8 * t)
            pr = random.randint(1, 3)
            pa = int(150 * fade * random.uniform(0.3, 1.0))
            if pa > 0 and 0 <= py < size:
                draw.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(150, 255, 180, pa))
        img = img.filter(ImageFilter.GaussianBlur(radius=1))
        img.save(d / f"{i + 1:04d}.png")


def generate_slash(out_dir: str, size: int = 320, frames: int = 18):
    """斩击特效：弧形刀光 + 拖尾"""
    d = Path(out_dir); d.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        t = i / (frames - 1)
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = size // 2, size // 2
        # 弧形刀光
        swing = t * math.pi * 0.8 + math.pi * 0.1
        radius = int(size * 0.35)
        alpha = int(255 * (1 - t * 0.8))
        # 拖尾
        for trail in range(5):
            tt = max(0, t - trail * 0.04)
            ta = swing - trail * 0.15
            x1 = cx + int(radius * math.cos(ta - 0.3))
            y1 = cy + int(radius * math.sin(ta - 0.3))
            x2 = cx + int(radius * math.cos(ta + 0.1))
            y2 = cy + int(radius * math.sin(ta + 0.1))
            trail_alpha = int(alpha * (1 - trail * 0.2))
            if trail_alpha > 0:
                draw.line([(x1, y1), (x2, y2)], fill=(220, 240, 255, trail_alpha), width=max(1, 4 - trail))
        img = img.filter(ImageFilter.GaussianBlur(radius=1))
        img.save(d / f"{i + 1:04d}.png")


def generate_shield(out_dir: str, size: int = 288, frames: int = 20):
    """护盾特效：六边形网格 + 脉冲"""
    d = Path(out_dir); d.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        t = i / (frames - 1)
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        cx, cy = size // 2, size // 2
        pulse = 0.9 + 0.1 * math.sin(t * math.pi * 4)
        radius = int(size * 0.38 * pulse)
        fade = 1 - t * 0.5
        # 六边形
        points = []
        for k in range(6):
            angle = k * math.pi / 3 - math.pi / 6
            points.append((cx + int(radius * math.cos(angle)),
                           cy + int(radius * math.sin(angle))))
        alpha = int(150 * fade)
        draw.polygon(points, outline=(100, 180, 255, alpha))
        # 内六边形
        inner_r = int(radius * 0.6)
        inner_pts = []
        for k in range(6):
            angle = k * math.pi / 3
            inner_pts.append((cx + int(inner_r * math.cos(angle)),
                              cy + int(inner_r * math.sin(angle))))
        draw.polygon(inner_pts, outline=(100, 180, 255, int(alpha * 0.6)))
        # 填充
        draw.polygon(points, fill=(80, 150, 255, int(40 * fade)))
        img = img.filter(ImageFilter.GaussianBlur(radius=1))
        img.save(d / f"{i + 1:04d}.png")


# 注册表
EFFECTS = {
    "explosion":    (generate_explosion,    256, 30),
    "aura_loop":    (generate_aura_loop,    256, 40),
    "sparkle":      (generate_sparkle,       64, 12),
    "fire_ring":    (generate_fire_ring,    192, 24),
    "heal_effect":  (generate_heal_effect,  200, 30),
    "slash":        (generate_slash,        320, 18),
    "shield":       (generate_shield,       288, 20),
}


def generate_all(output_dir: str):
    """生成所有测试特效"""
    base = Path(output_dir)
    for name, (fn, size, frames) in EFFECTS.items():
        print(f"  生成 {name} ({size}x{size}, {frames}帧)...")
        fn(str(base / name), size, frames)
    print(f"✅ 全部生成完毕: {base}")


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "test_assets_vfx"
    generate_all(out)
