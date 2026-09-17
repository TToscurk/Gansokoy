"""改良版：用前景遮罩 + 顏色分佈比對 Tripo 預覽截圖與 landscape 原始預覽圖。

前一版失敗原因：整張灰階含網頁 UI，訊號被背景淹沒，且松樹/針葉林樹4 共用貼圖分數相同。
本版作法：
  1. 截圖先裁出預覽視窗，再用「背景為平滑漸層灰藍」的特性遮掉背景，只留模型前景。
  2. 參考圖同樣去背（Tripo 原圖背景為淺灰白）。
  3. 比對前景的 HSV 色彩直方圖 + 前景輪廓的高度剖面（每列寬度），兩者都對光照不敏感。
櫻花樹（粉紅）作為正確性檢驗：若它沒被正確認出，整個方法就不可信。
"""
import os
import glob
import numpy as np
from PIL import Image

SHOTS_DIR = r"C:\Users\B365\AppData\Roaming\Hermes\composer-images"
SHOTS = ["image_19ec37.png", "image_c53c4b.png", "image_bf0b69.png",
         "image_997e73.png", "image_106978.png"]
LS = r"D:\神社\shrine\godot\assets\landscape"


def rgb_to_hsv_arr(a):
    a = a.astype(np.float64) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(axis=-1)
    mn = a.min(axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-9
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & (mx == b) & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = ((b - r)[gm] / d[gm]) + 2
    h[bm] = ((r - g)[bm] / d[bm]) + 4
    h = h / 6.0
    s = np.where(mx > 1e-9, d / np.maximum(mx, 1e-9), 0.0)
    return h, s, mx


def foreground_mask(arr):
    """模型前景 = 非背景。背景是低飽和度的平滑灰/灰藍，且多半貼邊。"""
    h, s, v = rgb_to_hsv_arr(arr)
    # 取四邊的邊框像素當背景樣本
    H, W = v.shape
    band = max(2, min(H, W) // 40)
    border = np.concatenate([
        arr[:band].reshape(-1, 3), arr[-band:].reshape(-1, 3),
        arr[:, :band].reshape(-1, 3), arr[:, -band:].reshape(-1, 3)])
    bg = border.mean(axis=0)
    dist = np.linalg.norm(arr.astype(np.float64) - bg, axis=-1)
    m = (dist > 38) | (s > 0.22)
    # 去掉零星雜點：只保留有鄰居的像素
    p = np.pad(m.astype(np.uint8), 1)
    nb = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:])
    return m & (nb >= 2)


def crop_preview(img):
    """截圖中央的預覽視窗：網頁 UI 被暗化，預覽區明顯較亮。"""
    g = np.asarray(img.convert("L"), dtype=np.float64)
    H, W = g.shape
    bright = g > np.percentile(g, 70)
    rows = np.where(bright.mean(axis=1) > 0.45)[0]
    cols = np.where(bright.mean(axis=0) > 0.45)[0]
    if len(rows) > 20 and len(cols) > 20:
        return img.crop((cols[0], rows[0], cols[-1] + 1, rows[-1] + 1))
    return img


def tight_crop(img):
    """裁到前景邊界。"""
    arr = np.asarray(img.convert("RGB"))
    m = foreground_mask(arr)
    if m.sum() < 200:
        return img, None
    rows = np.where(m.any(axis=1))[0]
    cols = np.where(m.any(axis=0))[0]
    box = (cols[0], rows[0], cols[-1] + 1, rows[-1] + 1)
    return img.crop(box), box


def features(img):
    """回傳 (hue-sat 直方圖, 寬度剖面)。"""
    img = img.convert("RGB").resize((160, 160), Image.LANCZOS)
    arr = np.asarray(img)
    m = foreground_mask(arr)
    if m.sum() < 100:
        return None
    h, s, v = rgb_to_hsv_arr(arr)
    hh = h[m]
    ss = s[m]
    vv = v[m]
    # 2D 直方圖：色相 18 格 x 飽和 4 格，只算有彩度的像素
    hist, _, _ = np.histogram2d(hh, ss, bins=[18, 4],
                                range=[[0, 1], [0, 1]])
    hist = hist.flatten()
    hist = hist / max(hist.sum(), 1)
    # 明度直方圖補充灰階資訊
    vhist, _ = np.histogram(vv, bins=8, range=(0, 1))
    vhist = vhist / max(vhist.sum(), 1)
    # 輪廓：每列前景寬度（正規化）
    prof = m.sum(axis=1).astype(np.float64)
    prof = prof / max(prof.max(), 1)
    return np.concatenate([hist * 3.0, vhist * 1.0, prof * 0.5])


def dist(a, b):
    return float(np.linalg.norm(a - b))


refs = {}
for p in glob.glob(os.path.join(LS, "*_tripo_image_*.jpg")):
    tree = os.path.basename(p).split("_tripo_image_")[0]
    f = features(Image.open(p))
    if f is not None:
        refs.setdefault(tree, []).append((f, os.path.basename(p)))

print("參考庫:", ", ".join(f"{k}({len(v)}圖)" for k, v in sorted(refs.items())))
print()

summary = []
for s in SHOTS:
    sp = os.path.join(SHOTS_DIR, s)
    img = Image.open(sp)
    pv = crop_preview(img)
    tc, box = tight_crop(pv)
    f = features(tc)
    if f is None:
        print(f"{s}: 取不到前景")
        continue
    res = []
    for tree, items in refs.items():
        best = min(dist(f, rf) for rf, _ in items)
        res.append((best, tree))
    res.sort()
    top, second = res[0], res[1]
    margin = (second[0] - top[0]) / max(top[0], 1e-6) * 100
    print(f"=== {s}  預覽{pv.size} 前景{tc.size}")
    for sc, tree in res[:4]:
        print(f"    {sc:7.4f}  {tree}")
    print(f"    -> {top[1]}  領先第二名 {margin:.1f}%")
    print()
    summary.append((s, top[1], margin, second[1]))

print("=" * 60)
print("總表（領先 <10% 視為不可靠，需人工確認）")
for s, tree, m, second in summary:
    flag = "OK" if m >= 10 else "不可靠"
    print(f"  {s:20s} -> {tree:10s} 領先{m:5.1f}% [{flag}]  次: {second}")
