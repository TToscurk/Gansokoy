# P13 W3B：水面の白い高光（glare）の数値比較。glare_<spot>_a<方位>_h<高さ> ごとに水面マスクの輝度分布を出す。
#   uv run --no-project --with pillow --with numpy python tools/p13/analyze_glare_w3b.py <dirA> <dirB>
import sys, os, glob, re
import numpy as np
from PIL import Image


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32)


def lum(a):
    return (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]) / 255.0


def view_stats(d, v):
    base = load(os.path.join(d, v + ".png"))
    mg = load(os.path.join(d, v + "__m_water.png"))
    m = (mg[..., 0] > 170) & (mg[..., 2] > 170) & (mg[..., 1] < 100)
    n = int(m.sum())
    if n < 80:
        return None
    L = lum(base)[m]
    return {"n": n, "mean": float(L.mean()), "p99": float(np.percentile(L, 99)), "max": float(L.max()),
            "w80": float((L > 0.80).mean()), "w65": float((L > 0.65).mean())}


def run(d):
    views = sorted(set(re.sub(r"__m_.*", "", os.path.basename(p))[:-4] if p.endswith(".png") and "__m_" not in p else None for p in glob.glob(os.path.join(d, "glare_*.png"))) - {None})
    out = {}
    for v in views:
        if not os.path.exists(os.path.join(d, v + "__m_water.png")):
            continue
        s = view_stats(d, v)
        if s:
            out[v] = s
    return out


if __name__ == "__main__":
    A, B = sys.argv[1], sys.argv[2]
    ra, rb = run(A), run(B)
    for tag, r in (("A", ra), ("B", rb)):
        if not r:
            print(tag, "（水面画素のある view なし）")
            continue
        spots = sorted(set(k.split("_a")[0] for k in r))
        print("== [%s] %s：水面が見える view %d" % (tag, os.path.basename(os.path.dirname(os.path.join(A if tag == 'A' else B, 'x'))), len(r)))
        for sp in spots:
            vs = {k: v for k, v in r.items() if k.startswith(sp + "_a")}
            tot_n = sum(v["n"] for v in vs.values())
            w80 = sum(v["w80"] * v["n"] for v in vs.values()) / tot_n
            w65 = sum(v["w65"] * v["n"] for v in vs.values()) / tot_n
            worst = max(vs.items(), key=lambda kv: kv[1]["max"])
            worst80 = max(vs.items(), key=lambda kv: kv[1]["w80"])
            print("   %-12s view %2d 水面画素 %7d 平均輝度 %.3f  >0.80 %.3f%%  >0.65 %.2f%%  最大 %.3f（%s）  最悪 >0.80 率 %.2f%%（%s）" % (
                sp, len(vs), tot_n, sum(v["mean"] * v["n"] for v in vs.values()) / tot_n, w80 * 100, w65 * 100, worst[1]["max"], worst[0].replace("glare_", ""),
                worst80[1]["w80"] * 100, worst80[0].replace("glare_", "")))
