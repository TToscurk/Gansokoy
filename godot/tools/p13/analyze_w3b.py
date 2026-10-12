# P13 W3B：同鏡位 Before／After の数値比較（土渠の黒帯・水面の白い高光）。
#   uv run --no-project --with pillow --with numpy python tools/p13/analyze_w3b.py <dirA> <dirB> [view ...]
# 画素マスク：構件（earth＝土渠メッシュ／water＝水面／struct＝木・石）を不透明マゼンタ（unshaded）に差し替えた画像のマゼンタ画素。
# 指標：earth の平均輝度・黒画素率（輝度 < 0.06）、water の平均輝度・白画素率（輝度 > 0.80）・p99。
import sys, os
import numpy as np
from PIL import Image

THR = 14.0  # 3ch 絶対差の合計（0–765）


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32)


def lum(a):
    return (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]) / 255.0


def dilate(m, r):
    out = m.copy()
    for dx in range(-r, r + 1):
        out |= np.roll(m, dx, axis=1)
    o2 = out.copy()
    for dy in range(-r, r + 1):
        o2 |= np.roll(out, dy, axis=0)
    return o2


def stats(d, view):
    base = load(os.path.join(d, view + ".png"))
    out = {}
    L = lum(base)
    masks = {}
    for k in ("earth", "water", "struct"):
        p = os.path.join(d, "%s__m_%s.png" % (view, k))
        if os.path.exists(p):
            mg = load(p)
            masks[k] = (mg[..., 0] > 170) & (mg[..., 2] > 170) & (mg[..., 1] < 100)
    anym = np.zeros(L.shape, bool)
    for m in masks.values():
        anym |= m
    ring = dilate(anym, 14) & ~anym
    out["_ring"] = {"n": int(ring.sum()), "mean": float(L[ring].mean()), "rgb": [float(base[..., c][ring].mean()) for c in range(3)]} if ring.sum() else {"n": 0}
    for k in ("earth", "water", "struct"):
        p = os.path.join(d, "%s__m_%s.png" % (view, k))
        if not os.path.exists(p):
            continue
        mg = load(p)
        m = (mg[..., 0] > 170) & (mg[..., 2] > 170) & (mg[..., 1] < 100)
        n = int(m.sum())
        if n < 50:
            out[k] = {"n": n}
            continue
        v = L[m]
        out[k] = {"n": n, "rgb": [float(base[..., c][m].mean()) for c in range(3)], "mean": float(v.mean()), "p5": float(np.percentile(v, 5)), "p50": float(np.percentile(v, 50)), "p95": float(np.percentile(v, 95)),
                  "p99": float(np.percentile(v, 99)), "black": float((v < 0.06).mean()), "white": float((v > 0.80).mean())}
    return out


def fmt(s):
    if "mean" not in s:
        return "n=%d（画素なし）" % s["n"]
    return ("RGB(%3.0f,%3.0f,%3.0f) " % tuple(s["rgb"]) if "rgb" in s else "") + "n=%6d 平均%.3f p5 %.3f p50 %.3f p95 %.3f p99 %.3f 黒(<0.06) %5.1f%% 白(>0.80) %5.1f%%" % (s["n"], s["mean"], s["p5"], s["p50"], s["p95"], s["p99"], s["black"] * 100, s["white"] * 100)


if __name__ == "__main__":
    A, B = sys.argv[1], sys.argv[2]
    views = sys.argv[3:] or ["T0_down_tps", "T0_up_tps", "N0_tps", "high_farm"]
    for v in views:
        for tag, d in (("A", A), ("B", B)):
            if not os.path.exists(os.path.join(d, v + ".png")):
                continue
            st = stats(d, v)
            print("== %s [%s]" % (v, tag))
            for k in ("earth", "water", "struct", "_ring"):
                if k in st and "mean" in st[k]:
                    print("   %-6s %s" % (k if k != "_ring" else "周囲地面", fmt(st[k]) if k != "_ring" else "RGB(%3.0f,%3.0f,%3.0f) n=%d 平均輝度%.3f" % (tuple(st[k]["rgb"]) + (st[k]["n"], st[k]["mean"]))))
