# P13 W3B：木槽まわりの「暗い隙間」の前後比較（同鏡位）。
#   uv run --no-project --with pillow --with numpy python tools/p13/analyze_dark_w3b.py <beforeDir> <afterDir>
# (1) TPS（T0_down／T0_up）：木構件マスク（struct）を dilate した帯（ring）のうち、マスク外の画素の暗画素率（輝度 < 0.08／< 0.05）。
#     ring は「槽の真下・すぐ脇の地面／土」にあたる。槽の下の隙間が黒く見えるなら、ここの暗画素率が高い。
# (2) 木槽の近景（seam_T0_*_trough_*）：画面全体の暗画素率（輝度 < 0.05）。近景は槽が主題なので全画面でも槽下の隙間が支配的。
import os
import sys

import numpy as np
from PIL import Image


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


def mask(d, view, k):
    p = os.path.join(d, "%s__m_%s.png" % (view, k))
    if not os.path.exists(p):
        return None
    mg = load(p)
    return (mg[..., 0] > 170) & (mg[..., 2] > 170) & (mg[..., 1] < 100)


def ring_stats(d, view, r):
    L = lum(load(os.path.join(d, view + ".png")))
    st = mask(d, view, "struct")
    allm = np.zeros(L.shape, bool)
    for k in ("earth", "water", "struct"):
        m = mask(d, view, k)
        if m is not None:
            allm |= m
    ring = dilate(st, r) & ~allm
    v = L[ring]
    return int(ring.sum()), float((v < 0.08).mean()), float((v < 0.05).mean()), float(v.mean()), float(np.percentile(v, 5))


def main():
    a, b = sys.argv[1], sys.argv[2]
    ma = sys.argv[3] if len(sys.argv) > 3 else a
    mb = sys.argv[4] if len(sys.argv) > 4 else b
    print("== (1) TPS：木構件の周り ring（マスク外）の暗画素率")
    for view in ("T0_down_tps", "T0_up_tps", "N0_tps", "high_farm"):
        for r in (6, 14):
            try:
                na, a8, a5, am, ap5 = ring_stats(ma, view, r)
                nb, b8, b5, bm, bp5 = ring_stats(mb, view, r)
            except Exception as e:  # noqa: BLE001
                print("  %-12s r=%2d 計測不可：%s" % (view, r, e))
                continue
            print("  %-12s r=%2d  画素 %6d→%6d  <0.08：%5.1f%%→%5.1f%%  <0.05：%5.1f%%→%5.1f%%  平均輝度 %.3f→%.3f  p5 %.3f→%.3f" % (view, r, na, nb, a8 * 100, b8 * 100, a5 * 100, b5 * 100, am, bm, ap5, bp5))
    print("== (2) 木槽の近景：画面全体の暗画素率（輝度 < 0.05／< 0.08）")
    names = sorted(f[:-4] for f in os.listdir(b) if f.startswith("seam_T0_") and "_trough_" in f and f.endswith(".png") and "__m_" not in f)
    tot_a = []
    tot_b = []
    for n in names:
        pa = os.path.join(a, n + ".png")
        if not os.path.exists(pa):
            continue
        La = lum(load(pa))
        Lb = lum(load(os.path.join(b, n + ".png")))
        tot_a.append((La < 0.05).mean())
        tot_b.append((Lb < 0.05).mean())
        print("  %-34s  <0.05：%5.2f%%→%5.2f%%   <0.08：%5.2f%%→%5.2f%%" % (n, (La < 0.05).mean() * 100, (Lb < 0.05).mean() * 100, (La < 0.08).mean() * 100, (Lb < 0.08).mean() * 100))
    if tot_a:
        print("  平均（%d 枚）<0.05：%.2f%%→%.2f%%" % (len(tot_a), np.mean(tot_a) * 100, np.mean(tot_b) * 100))


main()
