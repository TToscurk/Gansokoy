"""P13 Wave 6：ID パスと通常画像の突き合わせ解析（唯読）。

  uv run --with pillow --with numpy python w6_analyze.py <survey_dir> <tag> [--shots=0,5,7] [--csv=out.csv]

各ショット：
  1. 道路ノード（Roads/…、RoadBaseP10 差し替え後も同じパス）と地形系ノードの境界画素対を集め、境界をまたぐ輝度プロファイル（k=0..8 px）を平均する
     → 暗縫なら k=0 の谷。道路側・地面側を別に出す。
  2. 境界の鮮鋭度＝境界対の RGB 距離の平均、境界長（px）をノード対ごとに集計。
  3. 地形ノード内の「淡色の外れ画素」：同一ノード画素の局所平均（31px 箱）より明るい画素の連結成分（小さいもの）を数え、ノード別に帰属。
"""
import json
import sys
from collections import defaultdict

import numpy as np
from PIL import Image


def load_table(path):
    d = json.load(open(path, encoding="utf-8"))
    return int(d["bits"]), {int(k): v for k, v in d["map"].items()}


def decode(img_path, bits):
    a = np.asarray(Image.open(img_path).convert("RGB")).astype(np.int32)
    sp = 8 if bits == 5 else 4
    half = sp // 2
    q = np.clip((a - half + sp // 2) // sp, 0, (1 << bits) - 1)
    back = q * sp + half
    err = np.abs(a - back).max(axis=2)
    ids = (q[..., 0] << (2 * bits)) | (q[..., 1] << bits) | q[..., 2]
    tol = 1 if bits == 6 else 2
    return np.where(err <= tol, ids, -1)


def label_of(path):
    p = path.split("/")
    if p[0] == "Roads":
        if len(p) > 1 and p[1] == "Bridges":
            return "BR"
        return "R:" + "/".join(p[1:3]) if len(p) >= 3 else "R:" + path
    if p[0] == "Terrain":
        return "T:" + p[1]
    if p[0] == "Vegetation" and len(p) > 2 and p[1] == "GroundcoverP9":
        return "GC:" + "/".join(p[2:4])
    if p[0] == "Vegetation" and len(p) > 2 and p[2] in ("Ground",):
        return "OVG:" + p[1]
    if p[0] == "Districts" and len(p) > 2 and "Yard" in p[2]:
        return "Y:" + p[1]
    return "O:" + "/".join(p[:2])


def luminance(rgb):
    return (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]) / 255.0


def box_mean(a, mask, r):
    """マスク内画素だけの局所平均（箱 (2r+1)^2）"""
    m = mask.astype(np.float64)
    v = np.where(mask, a, 0.0)
    def integ(x):
        c = np.cumsum(np.cumsum(x, 0), 1)
        return np.pad(c, ((1, 0), (1, 0)))
    H, W = a.shape
    iv, im = integ(v), integ(m)
    y0 = np.clip(np.arange(H) - r, 0, H)
    y1 = np.clip(np.arange(H) + r + 1, 0, H)
    x0 = np.clip(np.arange(W) - r, 0, W)
    x1 = np.clip(np.arange(W) + r + 1, 0, W)
    def rect(I):
        return I[y1][:, x1] - I[y0][:, x1] - I[y1][:, x0] + I[y0][:, x0]
    s, n = rect(iv), rect(im)
    return np.where(n > 0, s / np.maximum(n, 1), 0.0), n


def components(mask, minpx=8):
    """4 連結成分（反復ラベリング、画像が小さいので素朴実装）"""
    H, W = mask.shape
    lab = np.zeros((H, W), np.int32)
    n = 0
    out = []
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys, xs):
        if lab[y, x]:
            continue
        n += 1
        stack = [(y, x)]
        lab[y, x] = n
        pts = []
        while stack:
            cy, cx = stack.pop()
            pts.append((cy, cx))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = n
                    stack.append((ny, nx))
        if len(pts) >= minpx:
            out.append(pts)
    return out


def analyze(img_path, id_path, bits, mp, labcache):
    rgb = np.asarray(Image.open(img_path).convert("RGB")).astype(np.float64)
    ids = decode(id_path, bits)
    H, W = ids.shape
    L = luminance(rgb)
    labs = np.full(ids.shape, "", dtype=object)
    uniq = np.unique(ids[ids >= 0])
    lab_of_id = {}
    for u in uniq:
        p = mp.get(int(u))
        if p is None:
            continue
        if p not in labcache:
            labcache[p] = label_of(p)
        lab_of_id[int(u)] = labcache[p]
    # ラベルを整数コードへ
    names = sorted(set(lab_of_id.values()))
    code_of = {n: i + 1 for i, n in enumerate(names)}
    code = np.zeros(ids.shape, np.int32)
    for u, n in lab_of_id.items():
        code[ids == u] = code_of[n]
    is_road = np.zeros(len(names) + 1, bool)
    is_ground = np.zeros(len(names) + 1, bool)
    for n, c in code_of.items():
        if n.startswith("R:"):
            is_road[c] = True
        if n.startswith(("T:", "GC:", "OVG:", "Y:")):
            is_ground[c] = True
    res = {"pairs": defaultdict(lambda: [0, 0.0]), "prof_road": np.zeros(9), "prof_ground": np.zeros(9), "nprof": 0, "area": defaultdict(int)}
    for n, c in code_of.items():
        res["area"][n] = int((code == c).sum())
    # 水平・垂直の境界対（road 画素 p と ground 画素 q が隣接）
    for axis in (0, 1):
        if axis == 1:
            a, b = code[:, :-1], code[:, 1:]
            ra, rb = rgb[:, :-1], rgb[:, 1:]
        else:
            a, b = code[:-1, :], code[1:, :]
            ra, rb = rgb[:-1, :], rgb[1:, :]
        m1 = is_road[a] & is_ground[b]
        m2 = is_ground[a] & is_road[b]
        for m, road_first in ((m1, True), (m2, False)):
            ys, xs = np.nonzero(m)
            if ys.size == 0:
                continue
            for y, x in zip(ys, xs):
                ca, cb = a[y, x], b[y, x]
                key = (names[ca - 1], names[cb - 1]) if road_first else (names[cb - 1], names[ca - 1])
                d = float(np.abs(ra[y, x] - rb[y, x]).sum()) / 3.0
                e = res["pairs"][key]
                e[0] += 1
                e[1] += d
            # プロファイル（輝度）：road 側 k 歩戻る／ground 側 k 歩進む
            sel = np.nonzero(m)
            if ys.size > 4000:
                pick = np.random.RandomState(1).choice(ys.size, 4000, replace=False)
                py, px = ys[pick], xs[pick]
            else:
                py, px = ys, xs
            for y, x in zip(py, px):
                if axis == 1:
                    ok = x - 8 >= 0 and x + 9 < W
                    if not ok:
                        continue
                    seg = L[y, x - 8:x + 10]          # 18 画素：x-8..x+9、境界は x|x+1 の間
                else:
                    ok = y - 8 >= 0 and y + 9 < H
                    if not ok:
                        continue
                    seg = L[y - 8:y + 10, x]
                first = seg[:9][::-1]                 # a 側（境界から離れる向き）k=0..8
                second = seg[9:]                      # b 側
                if road_first:
                    res["prof_road"] += first
                    res["prof_ground"] += second
                else:
                    res["prof_road"] += second
                    res["prof_ground"] += first
                res["nprof"] += 1
    return res, code, names, L, lab_of_id


def pale_outliers(L, code, names, ids, mp, thresh=0.10, minpx=12, maxpx=3000):
    """地形系ノード内の局所平均より明るい画素の連結成分（淡色断片の候補）"""
    out = []
    for n in names:
        if not n.startswith(("T:", "GC:", "OVG:")):
            continue
    ground_codes = [i + 1 for i, n in enumerate(names) if n.startswith(("T:", "GC:", "OVG:"))]
    if not ground_codes:
        return out
    gmask = np.isin(code, ground_codes)
    mean, cnt = box_mean(L, gmask, 15)
    m = gmask & (cnt > 400) & (L > mean + thresh) & (L > 0.18)
    for pts in components(m, minpx):
        if len(pts) > maxpx:
            continue
        ys = np.array([p[0] for p in pts])
        xs = np.array([p[1] for p in pts])
        cc = np.bincount(code[ys, xs], minlength=len(names) + 1)
        top = int(cc.argmax())
        out.append({"px": len(pts), "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())], "node": names[top - 1] if top > 0 else "?",
                    "gain": float((L[ys, xs] - mean[ys, xs]).mean())})
    out.sort(key=lambda r: -r["px"])
    return out


def main():
    d = sys.argv[1].rstrip("/")
    tag = sys.argv[2]
    shots = None
    for a in sys.argv[3:]:
        if a.startswith("--shots="):
            shots = [int(x) for x in a.split("=")[1].split(",")]
    idx = json.load(open(f"{d}/{tag}_index.json", encoding="utf-8"))
    bits, mp = load_table(f"{d}/{tag}_idtable.json")
    labcache = {}
    agg_pairs = defaultdict(lambda: [0, 0.0])
    agg_prof = {"road": np.zeros(9), "ground": np.zeros(9), "n": 0}
    rows = []
    for r in idx:
        i = r["i"]
        if shots is not None and i not in shots:
            continue
        res, code, names, L, lab_of_id = analyze(f"{d}/{r['name']}.png", f"{d}/{tag}_{i:03d}_id.png", bits, mp, labcache)
        n = max(res["nprof"], 1)
        pr = res["prof_road"] / n
        pg = res["prof_ground"] / n
        # 暗縫指標：境界直近 (k=0,1) の平均輝度 ÷ min(道路側 k=4..8 平均, 地面側 k=4..8 平均)
        base_r = pr[4:].mean() if res["nprof"] else 0
        base_g = pg[4:].mean() if res["nprof"] else 0
        seam = (pr[:2].mean() + pg[:2].mean()) / 2.0 / max(min(base_r, base_g), 1e-4) if res["nprof"] else float("nan")
        bsum = sum(v[0] for v in res["pairs"].values())
        print(f"#{i:02d} {r['seg'][:12]:12s} s={r['s']:6.1f} boundary_px={bsum:6d} seam_ratio={seam:5.2f} (prof_r k0..{pr[0]:.3f} k8 {pr[8]:.3f} | prof_g k0 {pg[0]:.3f} k8 {pg[8]:.3f})")
        for k, v in sorted(res["pairs"].items(), key=lambda kv: -kv[1][0])[:4]:
            print(f"      {k[0]:34s} | {k[1]:30s} n={v[0]:5d} dRGB={v[1]/max(v[0],1):5.1f}")
            agg_pairs[k][0] += v[0]
            agg_pairs[k][1] += v[1]
        agg_prof["road"] += res["prof_road"]
        agg_prof["ground"] += res["prof_ground"]
        agg_prof["n"] += res["nprof"]
        rows.append((i, seam, bsum))
    print("\n=== 全ショット合計の境界対（road × ground） ===")
    for k, v in sorted(agg_pairs.items(), key=lambda kv: -kv[1][0])[:25]:
        print(f"  {k[0]:34s} | {k[1]:30s} n={v[0]:7d} dRGB={v[1]/max(v[0],1):5.1f}")
    n = max(agg_prof["n"], 1)
    print("\n=== 平均輝度プロファイル（境界から k px、0..8） ===")
    print("  road  :", " ".join(f"{x:.3f}" for x in agg_prof["road"] / n))
    print("  ground:", " ".join(f"{x:.3f}" for x in agg_prof["ground"] / n))


if __name__ == "__main__":
    main()
