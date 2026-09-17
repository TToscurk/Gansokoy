"""把使用者貼的 Tripo 預覽截圖，比對 assets/landscape/ 內的 *_tripo_image_*.jpg 原始預覽圖。
截圖是「網頁預覽視窗」的畫面，需先裁出中央模型區再比對。
用多尺度灰階 RMSE + 邊緣結構相似度，輸出每張截圖的最佳匹配樹種。
"""
import os
import glob
import numpy as np
from PIL import Image

SHOTS_DIR = r"C:\Users\B365\AppData\Roaming\Hermes\composer-images"
SHOTS = ["image_19ec37.png", "image_c53c4b.png", "image_bf0b69.png",
         "image_997e73.png", "image_106978.png"]
LS = r"D:\神社\shrine\godot\assets\landscape"

N = 96


def prep(img):
    """灰階 + 正規化到 NxN + 去除亮度/對比差異。"""
    g = img.convert("L").resize((N, N), Image.LANCZOS)
    a = np.asarray(g, dtype=np.float64)
    a = (a - a.mean()) / (a.std() + 1e-6)
    return a


def edges(a):
    gx = np.abs(np.diff(a, axis=1))[:-1, :]
    gy = np.abs(np.diff(a, axis=0))[:, :-1]
    e = np.sqrt(gx ** 2 + gy ** 2)
    return (e - e.mean()) / (e.std() + 1e-6)


def score(a, b):
    """越小越像：像素 RMSE 與邊緣 RMSE 的加權。"""
    px = np.sqrt(((a - b) ** 2).mean())
    ed = np.sqrt(((edges(a) - edges(b)) ** 2).mean())
    return 0.5 * px + 0.5 * ed


def autocrop_subject(img):
    """截圖中央是模型預覽；裁掉週邊暗化的網頁介面。
    作法：找出畫面中最亮的大塊連續區域（預覽視窗背景是亮灰藍）。"""
    g = np.asarray(img.convert("L"), dtype=np.float64)
    h, w = g.shape
    thr = np.percentile(g, 75)
    mask = g > thr
    rows = np.where(mask.sum(axis=1) > w * 0.25)[0]
    cols = np.where(mask.sum(axis=0) > h * 0.25)[0]
    if len(rows) < 10 or len(cols) < 10:
        return img
    y0, y1 = rows[0], rows[-1]
    x0, x1 = cols[0], cols[-1]
    if (y1 - y0) < h * 0.2 or (x1 - x0) < w * 0.2:
        return img
    return img.crop((x0, y0, x1 + 1, y1 + 1))


# 建立參考庫：每棵樹的 tripo 預覽圖
refs = {}
for p in glob.glob(os.path.join(LS, "*_tripo_image_*.jpg")):
    name = os.path.basename(p)
    tree = name.split("_tripo_image_")[0]
    refs.setdefault(tree, []).append(p)

print("參考庫樹種:", ", ".join(sorted(refs)))
print()

for s in SHOTS:
    sp = os.path.join(SHOTS_DIR, s)
    if not os.path.exists(sp):
        print(f"{s}: 檔案不存在")
        continue
    img = Image.open(sp)
    crop = autocrop_subject(img)
    variants = [prep(crop), prep(img)]
    results = []
    for tree, paths in refs.items():
        best = min(
            score(v, prep(Image.open(rp)))
            for rp in paths for v in variants
        )
        results.append((best, tree, os.path.basename(min(paths))))
    results.sort()
    print(f"=== {s}  (原圖 {img.size}, 裁後 {crop.size})")
    for sc, tree, _ in results[:4]:
        print(f"    {sc:7.4f}  {tree}")
    top, second = results[0][0], results[1][0]
    margin = (second - top) / max(top, 1e-6)
    verdict = "明確" if margin > 0.08 else "差距太小,不可靠"
    print(f"    -> 最佳: {results[0][1]}  (領先第二名 {margin*100:.1f}%, {verdict})")
    print()
