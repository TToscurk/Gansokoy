"""傳送點地面光印貼圖產生器（docs/reference/傳送點美術/幻想鄉神社傳送點設計提案.png）。

產出（godot/assets/portal/）：
  seal_stone.png   石盤：風化灰褐圓盤＋分段石圈＋刻線（albedo，alpha＝覆蓋）
  seal_core.png    中央櫻花紋＋內外同心環（emission 用；白色，alpha＝亮度）
  seal_glyph.png   結界符紋帶＋外圈斷續弧（emission 用；會慢速旋轉的那層）
  petal.png        花瓣粒子
  mote.png         光粒
重跑：python godot/tools/portal/make_portal_textures.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "portal")
S = 1024          # 貼圖邊長（像素）；對應地面 3.8 m 方框
C = S / 2.0
R = S / 2.0       # 正規化半徑 1.0 = 貼圖半邊


def px(r):
    return r * R


def ring(draw, r, w, a=255):
    rr = px(r)
    draw.ellipse([C - rr, C - rr, C + rr, C + rr], outline=(255, 255, 255, a), width=max(1, int(w)))


def arc(draw, r, a0, a1, w, a=255):
    rr = px(r)
    draw.arc([C - rr, C - rr, C + rr, C + rr], a0, a1, fill=(255, 255, 255, a), width=max(1, int(w)))


def polar(r, ang):
    return (C + px(r) * math.cos(ang), C + px(r) * math.sin(ang))


def petal_poly(cx, cy, length, width, ang, notch=0.17, n=64):
    """一片櫻花瓣：瓣根收窄、瓣肩飽滿、瓣端中央 V 形缺刻。以 (cx,cy) 為花心、朝 ang 方向。"""
    pts = []
    for i in range(n + 1):
        t = i / n                      # 0..1 沿一側（瓣根→瓣肩）
        y = t * length * 0.94
        if t < 0.72:
            hw = width * math.sin(math.pi / 2 * t / 0.72) ** 0.85
        else:
            hw = width * math.cos((t - 0.72) / 0.28 * math.pi / 2 * 0.55)
        pts.append((y, hw))
    left = [(y, h) for y, h in pts]
    right = [(y, -h) for y, h in reversed(pts)]
    tip_notch = [(length * (1.0 - notch), 0.0)]     # 缺刻底；兩側瓣肩停在 y≈0.94L、半寬≈0.57W
    shape = left + tip_notch + right
    out = []
    ca, sa = math.cos(ang), math.sin(ang)
    for y, h in shape:
        out.append((cx + y * ca - h * sa, cy + y * sa + h * ca))
    return out


def sakura(draw, cx, cy, size, rot, fill_a, line_a, line_w, stamens=True):
    for k in range(5):
        ang = rot + k * 2 * math.pi / 5 - math.pi / 2
        # 瓣根離花心一點距離，五瓣不在中心擠成一團
        bx, by = cx + size * 0.06 * math.cos(ang), cy + size * 0.06 * math.sin(ang)
        poly = petal_poly(bx, by, size * 0.94, size * 0.40, ang)
        draw.polygon(poly, fill=(255, 255, 255, fill_a))
        draw.line(poly + [poly[0]], fill=(255, 255, 255, line_a), width=line_w, joint="curve")
    if not stamens:
        return
    # 花蕊：細、略暗（主次：花瓣輪廓 > 花蕊）
    sa = int(line_a * 0.7)
    for k in range(10):
        ang = rot + (k + 0.5) * 2 * math.pi / 10
        x2, y2 = cx + size * 0.22 * math.cos(ang), cy + size * 0.22 * math.sin(ang)
        draw.line([(cx, cy), (x2, y2)], fill=(255, 255, 255, sa), width=max(1, line_w // 3))
        rr = max(2, line_w // 2)
        draw.ellipse([x2 - rr, y2 - rr, x2 + rr, y2 + rr], fill=(255, 255, 255, sa))
    draw.ellipse([cx - size * 0.05, cy - size * 0.05, cx + size * 0.05, cy + size * 0.05], fill=(255, 255, 255, sa))


def glow(img, radius, gain):
    """加柔光：模糊後疊回。"""
    a = img.split()[3]
    blur = a.filter(ImageFilter.GaussianBlur(radius))
    blur = blur.point(lambda v: min(255, int(v * gain)))
    merged = ImageChops.lighter(a, blur)
    out = Image.new("RGBA", img.size, (255, 255, 255, 0))
    out.putalpha(merged)
    return out


def make_core():
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    # 主次：中央花（最亮）＞ 主圓環 ＞ 輔助細線
    sakura(d, C, C, px(0.27), 0.0, 80, 255, 6)
    ring(d, 0.335, 4, 215)
    for k in range(20):
        a0 = k * 18 + 3
        arc(d, 0.375, a0, a0 + 11, 3, 150)
    ring(d, 0.645, 5, 205)
    ring(d, 0.672, 2, 110)
    img = glow(img, 5, 1.2)
    return premul(img)


def shide(d, ang, r0, r1, a):
    """紙垂（御幣的之字形紙條）抽象化：沿徑向的三折之字。"""
    pts = []
    steps = 4
    for i in range(steps + 1):
        r = r0 + (r1 - r0) * i / steps
        off = (0.028 if i % 2 else -0.028) if 0 < i < steps else 0.0
        pts.append(polar(r, ang + off / max(r, 0.1)))
    d.line(pts, fill=(255, 255, 255, a), width=4, joint="curve")


def make_glyph():
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    n = 20
    for k in range(n):
        ang = 2 * math.pi * k / n
        if k % 4 == 0:
            x, y = polar(0.52, ang)                      # 小櫻（呼應中央）
            sakura(d, x, y, px(0.05), ang, 100, 235, 3, stamens=False)
        elif k % 2 == 1:
            shide(d, ang, 0.475, 0.57, 215)               # 紙垂
        else:
            for f, rr in ((0.50, 0.011), (0.545, 0.008)):  # 結界點（雙點）
                x, y = polar(f, ang)
                q = px(rr)
                d.ellipse([x - q, y - q, x + q, y + q], fill=(255, 255, 255, 200))
    ring(d, 0.455, 2, 120)
    ring(d, 0.59, 2, 120)
    # 外圈斷續弧（結界）
    for k in range(12):
        a0 = k * 30 + 4
        arc(d, 0.78, a0, a0 + 21, 4, 185)
        arc(d, 0.812, a0 + 6, a0 + 15, 2, 110)
    img = glow(img, 5, 1.3)
    return premul(img)


def blotch_field(size, cells, seed, blur):
    rnd = random.Random(seed)
    small = Image.new("L", (cells, cells))
    for y in range(cells):
        for x in range(cells):
            small.putpixel((x, y), rnd.randint(0, 255))
    return small.resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(blur))


def premul(img):
    """Decal 的 emission 只讀 RGB（不看 alpha）：發光層必須是黑底、RGB＝亮度，否則整個方框都會發白光。"""
    a = img.split()[3]
    return Image.merge("RGBA", (a, a, a, a))


def make_stone():
    rnd = random.Random(7)
    # 石面：大尺度磨損斑塊＋中尺度礦物色差＋很弱的細噪（不再滿版碎噪）
    big = blotch_field(S, 6, 11, 30)
    mid = blotch_field(S, 24, 12, 8)
    fine = Image.effect_noise((S, S), 14).convert("L")
    tone = Image.new("L", (S, S))
    tp, bp, mp, fp = tone.load(), big.load(), mid.load(), fine.load()
    for y in range(S):
        for x in range(S):
            v = 116 + (bp[x, y] - 128) * 0.20 + (mp[x, y] - 128) * 0.10 + (fp[x, y] - 128) * 0.25
            tp[x, y] = int(max(0, min(255, v)))
    col = Image.merge("RGB", [tone.point(lambda v, k=k: int(v * k)) for k in (1.04, 1.0, 0.93)])
    dc = ImageDraw.Draw(col)
    # 分段石圈（0.70–0.885）：接縫略暗、不全黑；段塊亮度各異
    n = 18
    for k in range(n):
        a0 = 360.0 * k / n
        a1 = 360.0 * (k + 1) / n
        shade = rnd.randint(-10, 8)
        for r in range(int(px(0.705)), int(px(0.88)), 2):
            dc.arc([C - r, C - r, C + r, C + r], a0 + 0.6, a1 - 0.6, fill=(122 + shade, 117 + shade, 108 + shade), width=2)
        ang = math.radians(a0)
        dc.line([polar(0.70, ang), polar(0.885, ang)], fill=(76, 72, 66), width=4)
    for r, w in ((0.70, 5), (0.885, 4)):
        rr = px(r)
        dc.ellipse([C - rr, C - rr, C + rr, C + rr], outline=(80, 76, 70), width=w)
    # 刻槽（光紋所在的淺溝）
    for r in (0.335, 0.645):
        rr = px(r)
        dc.ellipse([C - rr, C - rr, C + rr, C + rr], outline=(94, 90, 82), width=7)
    # 主裂縫 2 條＋少量分支
    for _ in range(2):
        ang = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.40, 0.55)
        pts = [polar(r, ang)]
        for _s in range(7):
            ang += rnd.uniform(-0.10, 0.10)
            r += rnd.uniform(0.035, 0.06)
            pts.append(polar(r, ang))
        dc.line(pts, fill=(84, 80, 74), width=3)
        b = rnd.randint(2, 4)
        dc.line([pts[b], polar(r - 0.12, ang + rnd.choice((-0.25, 0.25)))], fill=(90, 86, 79), width=2)
    # 盤緣崩角：外緣不規則
    alpha = Image.new("L", (S, S), 0)
    da = ImageDraw.Draw(alpha)
    edge = []
    for i in range(180):
        ang = 2 * math.pi * i / 180
        rr = 0.90 - (0.045 * max(0.0, math.sin(ang * 5 + 1.3)) ** 8) - (0.05 if rnd.random() < 0.05 else 0.0)
        edge.append(polar(rr, ang))
    da.polygon(edge, fill=255)
    alpha = alpha.filter(ImageFilter.GaussianBlur(5))
    # 苔：長在裂縫／石圈接縫與外緣的群聚，毛邊（模糊遮罩），深綠＋少量黃綠
    moss = Image.new("L", (S, S), 0)
    dm = ImageDraw.Draw(moss)
    for _ in range(26):
        ang = rnd.uniform(0, 2 * math.pi)
        r = rnd.choice((rnd.uniform(0.82, 0.9), rnd.uniform(0.69, 0.72)))
        for _j in range(rnd.randint(8, 22)):
            x, y = polar(r + rnd.uniform(-0.03, 0.03), ang + rnd.uniform(-0.07, 0.07))
            s = rnd.uniform(3, 11)
            dm.ellipse([x - s, y - s, x + s, y + s], fill=rnd.randint(150, 255))
    moss = moss.filter(ImageFilter.GaussianBlur(3))
    moss_col = Image.new("RGB", (S, S), (70, 86, 50))
    hi = Image.new("RGB", (S, S), (112, 124, 64))
    moss_col = Image.composite(hi, moss_col, mid.point(lambda v: 255 if v > 170 else 0))
    col = Image.composite(moss_col, col, moss.point(lambda v: int(v * 0.85)))
    col = col.filter(ImageFilter.GaussianBlur(0.8))
    img = col.convert("RGBA")
    img.putalpha(alpha)
    return img


def make_petal():
    s = 128
    img = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    poly = petal_poly(s * 0.5, s * 0.92, s * 0.84, s * 0.34, -math.pi / 2, notch=0.16)
    d.polygon(poly, fill=(255, 255, 255, 235))
    img = img.filter(ImageFilter.GaussianBlur(1.5))
    return img


def make_mote():
    s = 64
    img = Image.new("RGBA", (s, s), (255, 255, 255, 0))
    a = Image.new("L", (s, s), 0)
    for y in range(s):
        for x in range(s):
            r = math.hypot(x - s / 2 + 0.5, y - s / 2 + 0.5) / (s / 2)
            a.putpixel((x, y), int(255 * max(0.0, 1.0 - r) ** 2.2))
    img.putalpha(a)
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("seal_stone", make_stone), ("seal_core", make_core), ("seal_glyph", make_glyph),
                     ("petal", make_petal), ("mote", make_mote)):
        im = fn()
        p = os.path.join(OUT, name + ".png")
        im.save(p)
        print(name, im.size, os.path.getsize(p))
