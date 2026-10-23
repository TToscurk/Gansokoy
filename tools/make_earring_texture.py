"""產生緣一耳飾面板貼圖：彩繪玻璃風格的紅日 + 山稜。

依參考圖 D:/參考圖概念圖/.../繼國緣一/耳飾.PNG：
  暗金屬框 → 乳白天空 → 紅日圓盤 → 放射光芒（以深色鉛條呈現）
  → 灰色遠山 → 近乎黑的前景

面板實測 1.67 x 4.53 cm（比例 1:2.71），故貼圖取 512 x 1388。
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

W, H = 512, 1388
OUT_DIR = r"D:/神社/shrine/work/yoriichi_earring"

# 彩繪玻璃配色
LEAD = (38, 30, 26)          # 鉛條／外框（暗金屬）
SKY = (236, 230, 216)        # 乳白天空
SKY2 = (222, 214, 198)       # 天空的冷色暈
SUN = (150, 26, 28)          # 深紅／牛血紅
SUN_HI = (178, 42, 38)       # 日盤受光側
GREY = (138, 140, 146)       # 遠山灰
GREY2 = (86, 88, 95)         # 近山：與遠山拉開明度，小尺寸才分得出
DARK = (30, 28, 30)          # 前景近黑

FRAME = 26                   # 外框寬
LEADW = 9                    # 內部鉛條寬


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    img = Image.new("RGB", (W, H), SKY)
    d = ImageDraw.Draw(img)

    # --- 天空漸層（上淺下深一點，模擬玻璃厚薄）---
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=lerp(SKY, SKY2, t * 0.55))

    # --- 地平線分區 ---
    horizon1 = int(H * 0.615)       # 遠山稜線
    horizon2 = int(H * 0.775)       # 近山稜線
    ground = int(H * 0.875)         # 前景

    # 遠山（灰）：上凸弧
    pts = []
    for x in range(0, W + 1, 4):
        t = x / W
        y = horizon1 - int(math.sin(t * math.pi) * H * 0.045)
        pts.append((x, y))
    d.polygon(pts + [(W, horizon2), (0, horizon2)], fill=GREY)

    # 近山（深灰）：較淺的弧
    pts2 = []
    for x in range(0, W + 1, 4):
        t = x / W
        y = horizon2 - int(math.sin(t * math.pi + 0.6) * H * 0.025)
        pts2.append((x, y))
    d.polygon(pts2 + [(W, ground), (0, ground)], fill=GREY2)

    # 前景（近黑）
    d.rectangle([0, ground, W, H], fill=DARK)

    # --- 紅日 ---
    cx, cy = W // 2, int(H * 0.335)
    R = int(W * 0.30)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=SUN)
    # 受光側微亮
    d.ellipse([cx - R + 6, cy - R + 6, cx + R - 14, cy + R - 20],
              fill=SUN_HI)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=LEAD, width=LEADW)

    # --- 放射光芒：以鉛條表現，自日盤邊緣直接發出 ---
    # 耳飾實際只有 1.67 cm 寬，12 道會糊成一片，取 8 道並加粗。
    n_rays = 8
    RAYW = LEADW + 4
    for i in range(n_rays):
        a = math.pi * 2 * i / n_rays - math.pi / 2 + math.pi / n_rays
        # 自日盤外框起（不留間隙，鉛條才接得住）
        x0 = cx + math.cos(a) * (R - LEADW * 0.5)
        y0 = cy + math.sin(a) * (R - LEADW * 0.5)
        reach = W * 1.6
        x1 = cx + math.cos(a) * reach
        y1 = cy + math.sin(a) * reach
        # 向下的光芒被遠山擋住
        if y1 > horizon1:
            k = (horizon1 - cy) / max(y1 - cy, 1e-6)
            x1 = cx + (x1 - cx) * k
            y1 = horizon1
        d.line([(x0, y0), (x1, y1)], fill=LEAD, width=RAYW)
    # 光芒畫完再補日盤外框，蓋住接縫
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=LEAD, width=LEADW)

    # 地平線鉛條
    d.line(pts, fill=LEAD, width=LEADW + 2, joint="curve")
    d.line(pts2, fill=LEAD, width=LEADW + 2, joint="curve")
    d.line([(0, ground), (W, ground)], fill=LEAD, width=LEADW + 2)

    # --- 外框 ---
    d.rectangle([0, 0, W - 1, H - 1], outline=LEAD, width=FRAME)
    # 框內側微亮，模擬焊錫反光
    d.rectangle([FRAME - 3, FRAME - 3, W - FRAME + 2, H - FRAME + 2],
                outline=(92, 74, 58), width=3)

    img = img.filter(ImageFilter.SMOOTH)
    p = os.path.join(OUT_DIR, "earring_panel.png")
    img.save(p)
    print("WROTE", p, img.size)

    # 供預覽：放大三倍並排參考
    prev = img.resize((W // 2, H // 2), Image.LANCZOS)
    pp = os.path.join(OUT_DIR, "earring_panel_preview.png")
    prev.save(pp)
    print("WROTE", pp)


if __name__ == "__main__":
    main()
