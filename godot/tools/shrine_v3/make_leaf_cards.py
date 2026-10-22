"""博麗神社 v3 植被葉卡（程序繪製，RGBA，透明背景）。輸出 assets/shrine_v3/tex/veg/*.png。
  python tools/shrine_v3/make_leaf_cards.py
卡片約定：枝條基部在卡片「下緣中央」（Blender 端把卡片下緣掛在枝端）；上方＝枝梢方向。
春天：山櫻（白～淡粉花＋紅褐新葉）、闊葉新綠（枹櫟／欅）、野村楓（春紅葉）、杉、杜鵑（葉＋少量花）、草叢。
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(GODOT, 'assets', 'shrine_v3', 'tex', 'veg')
os.makedirs(OUT, exist_ok=True)
SS = 2   # 超取樣


def jit(c, a, rng):
    return tuple(max(0, min(255, int(v + rng.uniform(-a, a)))) for v in c)


def leaf_poly(cx, cy, length, width, ang, n=14, tip=1.0):
    """尖卵形葉：中心 (cx,cy) 為葉柄端，沿 ang 方向。"""
    pts_l = []
    pts_r = []
    for i in range(n + 1):
        t = i / n
        w = width * math.sin(math.pi * t) ** 0.8 * (1.0 - 0.35 * t ** 2.5 * tip)
        x = length * t
        pts_l.append((x, w))
        pts_r.append((x, -w))
    pts = pts_l + pts_r[::-1]
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def twig(d, p0, p1, w, col):
    d.line([p0, p1], fill=col, width=max(1, int(w)))


def branch_tree(rng, W, H, n_tips, spread=0.9, base_w=10):
    """在卡片內長一棵小枝系，回傳 [(線段, 粗細)] 與枝梢點。"""
    segs = []
    tips = []

    def grow(x, y, ang, L, w, depth):
        x2 = x + math.cos(ang) * L
        y2 = y + math.sin(ang) * L
        segs.append(((x, y), (x2, y2), w))
        if depth == 0 or L < 24:
            tips.append((x2, y2, ang))
            return
        k = 2 if depth > 1 else rng.randint(2, 3)
        for i in range(k):
            a2 = ang + rng.uniform(-spread, spread) * (0.6 if i == 0 else 1.0)
            grow(x2, y2, a2, L * rng.uniform(0.70, 0.86), w * 0.7, depth - 1)
        tips.append((x2, y2, ang))
    grow(W / 2, H - 4, -math.pi / 2 + rng.uniform(-0.1, 0.1), H * 0.20, base_w, n_tips)
    return segs, tips


def finish(im, name, blur=0.0):
    im = im.resize((im.width // SS, im.height // SS), Image.LANCZOS)
    if blur:
        im = im.filter(ImageFilter.GaussianBlur(blur))
    # 預乘邊緣的顏色擴張（避免 mip 時透明邊緣變黑）：把不透明像素的顏色往外擴
    a = np.asarray(im).astype(np.float32)
    rgb = a[..., :3]
    al = a[..., 3:4] / 255.0
    acc = rgb * al
    wsum = al.copy()
    for r in (2, 4, 8, 16):
        k = Image.fromarray(np.clip(acc, 0, 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(r))
        kw = Image.fromarray((np.clip(wsum[..., 0], 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(r))
        acc2 = np.asarray(k).astype(np.float32)
        w2 = np.asarray(kw).astype(np.float32)[..., None] / 255.0
        fill = (wsum < 0.01)
        acc = np.where(fill, acc2, acc)
        wsum = np.where(fill, w2, wsum)
    col = np.where(al > 0.01, rgb, acc / np.maximum(wsum, 1e-3))
    out = np.concatenate([np.clip(col, 0, 255), a[..., 3:4]], -1).astype(np.uint8)
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, name))
    print('[card] %-20s %s 覆蓋率 %.0f%%' % (name, im.size, 100.0 * float((a[..., 3] > 127).mean())))


def sakura():
    rng = random.Random(7)
    W = H = 1024 * SS
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    segs, tips = branch_tree(rng, W, H, 5, 0.85, 14 * SS)
    for (p0, p1, w) in segs:
        twig(d, p0, p1, w, (58, 40, 32, 255))
    # 紅褐新葉
    for (x, y, a) in tips:
        for k in range(rng.randint(1, 3)):
            ang = a + rng.uniform(-1.2, 1.2)
            pts = leaf_poly(x, y, rng.uniform(55, 80) * SS, rng.uniform(16, 22) * SS, ang)
            d.polygon(pts, fill=jit((128, 70, 46, 255), 16, rng))
    # 花團
    spots = list(tips)
    for (p0, p1, w) in segs:
        if w < 9 * SS:
            for t in (0.35, 0.7):
                spots.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, 0))
    for (x, y, a) in spots:
        for k in range(rng.randint(3, 6)):
            r = rng.uniform(20, 30) * SS
            cx = x + rng.uniform(-60, 60) * SS
            cy = y + rng.uniform(-60, 40) * SS
            if not (r < cx < W - r and r < cy < H - r):
                continue
            d.line([(x, y), (cx, cy)], fill=(70, 96, 40, 255), width=2 * SS)   # 花梗
            rot = rng.uniform(0, 2 * math.pi)
            base = jit((250, 226, 232, 255), 6, rng)
            for p in range(5):
                pa = rot + p * 2 * math.pi / 5
                px = cx + math.cos(pa) * r * 0.55
                py = cy + math.sin(pa) * r * 0.55
                pr = r * 0.52
                d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=base)
                # 花瓣尖端缺刻
                nx = cx + math.cos(pa) * r * 1.05
                ny = cy + math.sin(pa) * r * 1.05
                d.ellipse([nx - r * 0.13, ny - r * 0.13, nx + r * 0.13, ny + r * 0.13], fill=(0, 0, 0, 0))
            d.ellipse([cx - r * 0.28, cy - r * 0.28, cx + r * 0.28, cy + r * 0.28], fill=(232, 160, 176, 255))
            for s in range(6):
                sa = rng.uniform(0, 2 * math.pi)
                sx = cx + math.cos(sa) * r * 0.3
                sy = cy + math.sin(sa) * r * 0.3
                d.ellipse([sx - 2 * SS, sy - 2 * SS, sx + 2 * SS, sy + 2 * SS], fill=(196, 92, 110, 255))
    finish(im, 'sakura_card.png')


def broad(name, base, seed, leaf_len=(70, 105), leaf_w=(26, 36)):
    rng = random.Random(seed)
    W = H = 1024 * SS
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    segs, tips = branch_tree(rng, W, H, 5, 0.95, 11 * SS)
    for (p0, p1, w) in segs:
        twig(d, p0, p1, w, (62, 50, 38, 255))
    pts_all = []
    for (p0, p1, w) in segs:
        for t in np.linspace(0.2, 1.0, 4):
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
            for side in (-1, 1):
                pts_all.append((x, y, ang + side * rng.uniform(0.5, 1.1)))
    rng.shuffle(pts_all)
    for (x, y, ang) in pts_all:
        L = rng.uniform(*leaf_len) * SS
        Wd = rng.uniform(*leaf_w) * SS
        c = jit(base, 22, rng)
        pts = leaf_poly(x, y, L, Wd, ang)
        if all(0 < px < W and 0 < py < H for px, py in pts):
            d.polygon(pts, fill=c)
            # 中肋
            ex = x + math.cos(ang) * L * 0.9
            ey = y + math.sin(ang) * L * 0.9
            d.line([(x, y), (ex, ey)], fill=tuple(min(255, v + 28) for v in c[:3]) + (255,), width=SS)
    finish(im, name)


def momiji():
    rng = random.Random(23)
    W = H = 1024 * SS
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    segs, tips = branch_tree(rng, W, H, 5, 0.95, 10 * SS)
    for (p0, p1, w) in segs:
        twig(d, p0, p1, w, (70, 34, 30, 255))
    spots = []
    for (p0, p1, w) in segs:
        for t in (0.4, 0.75, 1.0):
            spots.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
    for (x, y) in spots:
        for k in range(rng.randint(2, 4)):
            r = rng.uniform(30, 44) * SS
            ang0 = rng.uniform(0, 2 * math.pi)
            cx = x + math.cos(ang0) * r * 0.9
            cy = y + math.sin(ang0) * r * 0.9
            d.line([(x, y), (cx, cy)], fill=(110, 30, 26, 255), width=2 * SS)
            c = jit((150, 30, 24, 255), 22, rng)
            axis = math.atan2(cy - y, cx - x)
            for li in range(7):
                la = axis + (li - 3) * 0.47
                L = r * (1.0 - 0.13 * abs(li - 3))
                pts = leaf_poly(cx, cy, L, L * 0.24, la, n=8)
                if all(0 < px < W and 0 < py < H for px, py in pts):
                    d.polygon(pts, fill=c)
            d.ellipse([cx - r * 0.24, cy - r * 0.24, cx + r * 0.24, cy + r * 0.24], fill=c)
    finish(im, 'momiji_card.png')


def sugi():
    rng = random.Random(31)
    W, H = 768 * SS, 1024 * SS
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # 主枝：自下緣中央往上，側枝成羽狀；每根小枝上密生短針葉
    stems = []

    def stem(x, y, ang, L, depth):
        x2 = x + math.cos(ang) * L
        y2 = y + math.sin(ang) * L
        stems.append(((x, y), (x2, y2), depth))
        if depth > 0:
            n = 6 if depth == 2 else 4
            for i in range(1, n + 1):
                t = i / (n + 1)
                bx = x + (x2 - x) * t
                by = y + (y2 - y) * t
                for side in (-1, 1):
                    stem(bx, by, ang + side * rng.uniform(0.6, 0.9), L * (0.42 - 0.18 * t), depth - 1)
    stem(W / 2, H - 4, -math.pi / 2, H * 0.92, 2)
    for (p0, p1, depth) in stems:
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        d.line([p0, p1], fill=(70, 66, 40, 255), width=max(SS, int((depth + 1) * 2 * SS)))
        n = int(L / (5 * SS))
        for i in range(n):
            t = i / max(n, 1)
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            for side in (-1, 1):
                a = ang + side * rng.uniform(0.35, 0.8)
                ln = rng.uniform(14, 24) * SS * (1.0 - 0.4 * t)
                c = jit((44, 70, 40, 255), 14, rng)
                d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=c, width=3 * SS)
    finish(im, 'sugi_card.png')


def tsutsuji():
    rng = random.Random(41)
    W = H = 1024 * SS
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    segs, tips = branch_tree(rng, W, H, 5, 1.05, 8 * SS)
    for (p0, p1, w) in segs:
        twig(d, p0, p1, w, (66, 52, 40, 255))
    for (p0, p1, w) in segs:
        for t in (0.4, 0.7, 1.0):
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            for k in range(7):
                ang = rng.uniform(0, 2 * math.pi)
                pts = leaf_poly(x, y, rng.uniform(38, 52) * SS, rng.uniform(13, 18) * SS, ang)
                if all(0 < px < W and 0 < py < H for px, py in pts):
                    d.polygon(pts, fill=jit((52, 88, 38, 255), 14, rng))
    for (x, y, a) in tips:
        if rng.random() < 0.55:
            for k in range(rng.randint(2, 4)):
                r = rng.uniform(22, 30) * SS
                cx = x + rng.uniform(-30, 30) * SS
                cy = y + rng.uniform(-30, 20) * SS
                c = jit((214, 82, 150, 255), 14, rng)
                for p in range(5):
                    pa = p * 2 * math.pi / 5 + rng.uniform(0, 1)
                    px = cx + math.cos(pa) * r * 0.5
                    py = cy + math.sin(pa) * r * 0.5
                    d.ellipse([px - r * 0.5, py - r * 0.5, px + r * 0.5, py + r * 0.5], fill=c)
                d.ellipse([cx - r * 0.2, cy - r * 0.2, cx + r * 0.2, cy + r * 0.2], fill=(240, 200, 220, 255))
    finish(im, 'tsutsuji_card.png')


def grass():
    rng = random.Random(53)
    W, H = 1024 * SS, 512 * SS
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for k in range(150):
        x0 = rng.uniform(0.08, 0.92) * W
        h = rng.uniform(0.45, 0.98) * H
        lean = rng.uniform(-0.35, 0.35)
        w0 = rng.uniform(5, 9) * SS
        base = jit((70, 104, 40, 255), 18, rng)
        tip = jit((150, 160, 80, 255), 18, rng)
        n = 10
        pts_l = []
        pts_r = []
        for i in range(n + 1):
            t = i / n
            x = x0 + lean * h * t * t
            y = H - h * t
            w = w0 * (1.0 - t) + 0.5
            pts_l.append((x - w, y))
            pts_r.append((x + w, y))
        poly = pts_l + pts_r[::-1]
        c = tuple(int(base[j] * 0.6 + tip[j] * 0.4) for j in range(3)) + (255,)
        d.polygon(poly, fill=c)
    # 少量小白花／黃花（春）
    for k in range(10):
        x = rng.uniform(0.1, 0.9) * W
        y = H - rng.uniform(0.3, 0.7) * H
        c = rng.choice([(240, 238, 225, 255), (236, 204, 70, 255)])
        r = rng.uniform(6, 9) * SS
        d.line([(x, y), (x + rng.uniform(-10, 10), H)], fill=(80, 110, 50, 255), width=2 * SS)
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    finish(im, 'grass_card.png')


def fern():
    rng = random.Random(61)
    W, H = 1024 * SS, 1024 * SS
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # 一片羽狀複葉：自下緣中央往上，彎曲
    n = 26
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append((W / 2 + math.sin(t * 1.4) * W * 0.12, H - t * H * 0.96))
    d.line(pts, fill=(70, 96, 40, 255), width=4 * SS)
    for i in range(2, n):
        t = i / n
        x, y = pts[i]
        L = (math.sin(t * math.pi) * 0.85 + 0.15) * W * 0.36
        for side in (-1, 1):
            ang = -math.pi / 2 + side * (1.25 - 0.4 * t)
            ex = x + math.cos(ang) * L
            ey = y + math.sin(ang) * L * 0.6
            c = jit((60, 104, 42, 255), 12, rng)
            m = 9
            for j in range(m):
                s = j / m
                px = x + (ex - x) * s
                py = y + (ey - y) * s
                ll = L * 0.12 * (1.0 - s * 0.8)
                for sd in (-1, 1):
                    a2 = ang + sd * 1.2
                    pts2 = leaf_poly(px, py, ll, ll * 0.35, a2, n=6)
                    d.polygon(pts2, fill=c)
            d.line([(x, y), (ex, ey)], fill=c, width=2 * SS)
    finish(im, 'fern_card.png')


if __name__ == '__main__':
    sakura()
    broad('broad_card.png', (88, 134, 46, 255), 11)
    broad('broad_dark_card.png', (52, 86, 36, 255), 13, (60, 90), (24, 32))
    momiji()
    sugi()
    tsutsuji()
    grass()
    fern()
