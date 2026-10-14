"""P13 Wave 6：淡色の外れ画素（地面系ノード内）の連結成分を全ショットで集計（唯読）。

  uv run --with pillow --with numpy python w6_pale.py <survey_dir> <tag> [--thresh=0.10] [--min=15] [--max=4000] [--annot=outdir] [--top=40]

地面系＝Terrain / 地被・院子 overlay の Ground / P8 EarthBanks / Districts の Yard / Roads（道路）。
局所平均（31px 箱、同じ地面系だけ）より明るい画素 (L > mean + thresh) の連結成分を数え、最大ノードで帰属する。
--annot を付けると、上位ショットに成分の bbox を赤枠で描いた画像を出力する（目視用）。
"""
import json
import sys
from collections import defaultdict

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
from w6_analyze import box_mean, components, decode, load_table, luminance  # noqa: E402


def kind(path):
    p = path.split("/")
    if p[0] == "Terrain":
        return "T:" + p[1]
    if p[0] == "Roads":
        return "BR" if len(p) > 1 and p[1] == "Bridges" else "R:" + "/".join(p[1:3])
    if p[0] == "Vegetation" and len(p) > 2 and (p[2] == "Ground" or p[2].startswith("Ground")):
        return "OVG:" + p[1] + ("/" + p[3] if p[1] == "GroundcoverP9" and len(p) > 3 else "")
    if "EarthBanks" in p:
        return "EB:" + "/".join(p[:3])
    if p[0] == "Districts" and len(p) > 2 and "Yard" in p[2]:
        return "Y:" + p[1]
    return ""


def main():
    d = sys.argv[1].rstrip("/")
    tag = sys.argv[2]
    thresh, minpx, maxpx, top = 0.10, 15, 4000, 40
    annot = None
    for a in sys.argv[3:]:
        if a.startswith("--thresh="):
            thresh = float(a.split("=")[1])
        elif a.startswith("--min="):
            minpx = int(a.split("=")[1])
        elif a.startswith("--max="):
            maxpx = int(a.split("=")[1])
        elif a.startswith("--annot="):
            annot = a.split("=", 1)[1]
        elif a.startswith("--top="):
            top = int(a.split("=")[1])
    idx = json.load(open(f"{d}/{tag}_index.json", encoding="utf-8"))
    bits, mp = load_table(f"{d}/{tag}_idtable.json")
    kcache = {}
    agg = defaultdict(lambda: [0, 0, 0.0])      # node → [components, px, gain*px]
    per_shot = []
    for r in idx:
        i = r["i"]
        ids = decode(f"{d}/{tag}_{i:03d}_id.png", bits)
        rgb = np.asarray(Image.open(f"{d}/{r['name']}.png").convert("RGB")).astype(np.float64)
        L = luminance(rgb)
        uniq = np.unique(ids[ids >= 0])
        names = []
        code = np.zeros(ids.shape, np.int32)
        for u in uniq:
            pth = mp.get(int(u))
            if pth is None:
                continue
            k = kcache.setdefault(pth, kind(pth))
            if not k or k == "BR":
                continue
            if k not in names:
                names.append(k)
            code[ids == u] = names.index(k) + 1
        gmask = code > 0
        if not gmask.any():
            continue
        mean, cnt = box_mean(L, gmask, 15)
        m = gmask & (cnt > 400) & (L > mean + thresh) & (L > 0.18)
        comps = []
        for pts in components(m, minpx):
            if len(pts) > maxpx:
                continue
            ys = np.array([p[0] for p in pts])
            xs = np.array([p[1] for p in pts])
            cc = np.bincount(code[ys, xs], minlength=len(names) + 1)
            t = int(cc.argmax())
            nd = names[t - 1] if t > 0 else "?"
            gain = float((L[ys, xs] - mean[ys, xs]).mean())
            comps.append({"px": len(pts), "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())], "node": nd, "gain": gain})
            e = agg[nd]
            e[0] += 1
            e[1] += len(pts)
            e[2] += gain * len(pts)
        comps.sort(key=lambda c: -c["px"])
        per_shot.append((i, r["name"], r["seg"], sum(c["px"] for c in comps), comps))
    print(f"=== {d} tag={tag} thresh={thresh} min={minpx} max={maxpx} ===")
    print("--- ノード別（成分数・総画素・平均 gain）---")
    for nd, (n, px, g) in sorted(agg.items(), key=lambda kv: -kv[1][1]):
        print(f"  {nd:46s} comps={n:5d} px={px:8d} gain={g / max(px, 1):.3f}")
    print("--- ショット別（淡色画素の多い順）---")
    ranked = sorted(per_shot, key=lambda t: -t[3])
    for i, nm, seg, px, comps in ranked[:top]:
        c0 = comps[0] if comps else None
        print(f"  #{i:03d} {seg[:22]:22s} pale_px={px:6d} comps={len(comps):3d}" + (f"  largest={c0['px']}px {c0['node']} bbox={c0['bbox']} gain={c0['gain']:.2f}" if c0 else ""))
    if annot:
        import os
        os.makedirs(annot, exist_ok=True)
        for i, nm, seg, px, comps in ranked[:12]:
            im = Image.open(f"{d}/{nm}.png").convert("RGB")
            dr = ImageDraw.Draw(im)
            for c in comps[:25]:
                x0, y0, x1, y1 = c["bbox"]
                dr.rectangle([x0 - 2, y0 - 2, x1 + 2, y1 + 2], outline=(255, 0, 0), width=2)
            im.save(f"{annot}/{tag}_{i:03d}_pale.png")
        print("annot →", annot)


if __name__ == "__main__":
    main()
