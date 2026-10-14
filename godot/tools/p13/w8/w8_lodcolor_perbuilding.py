"""P13 W8 TASK B：第一批 50 棟を『1 棟ずつ』に分けて、同鏡位・強制 LOD の壁／屋根の平均輝度を LOD0／1／2 で比べる（唯読）。
  uv run --quiet --with pillow --with numpy python w8_lodcolor_perbuilding.py <wave8 dir> <dir tag: lod_b_after2> [out.json] [--min-px=3000]
ID 画像の節点パス（Districts/<区>/Buildings/<ID>/Kit/LOD<k>/…）から建物 ID と LOD を取り、建物ごと・LOD ごとに画素を集計する。
同じ建物が複数の鏡位に写っていれば合算。LOD0／1／2 すべてで min-px 以上写っている建物だけを比較対象にする。
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, "D:/神社/shrine/godot/tools/p13/w6")
from w6_analyze import decode, load_table  # noqa: E402

W = Path(sys.argv[1])
tag = sys.argv[2]
out = None
minpx = 3000
VIEWS = ["mkt", "rsw", "mxc"]
for a in sys.argv[3:]:
    if a.startswith("--min-px="):
        minpx = int(a.split("=")[1])
    elif a.startswith("--views="):
        VIEWS = a[8:].split(",")
    elif not a.startswith("--"):
        out = a
batch = json.load(open("D:/神社/shrine/godot/data/village_v2_p13w7_batch1.json", encoding="utf-8"))["buildings"]
meta = {b["id"]: b for b in batch}
ROOF = ("rf_", "rg_", "udh_", "dmr_p", "oni_", "vg_", "his_", "hisx_", "l_rh_")
pat = re.compile(r"^Districts/[^/]+/Buildings/(B_[A-Z0-9_]+)/Kit/LOD(\d)/(.+)$")


def prefix(name):
    s = ""
    for ch in name:
        if ch.isdigit():
            break
        s += ch
    return s


def classify(path):
    m = pat.match(path)
    if not m or m.group(1) not in meta:
        return None
    pre = prefix(m.group(3).split("/")[-1])
    if pre.startswith("base_"):
        return None
    return m.group(1), int(m.group(2)), ("roof" if pre.startswith(ROOF) else "wall")


def luma(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


bits, mp = load_table(str(W / "diag" / tag / "l_idtable.json"))
cls = {k: classify(v) for k, v in mp.items()}
acc = {}
for v in VIEWS:
    for k in range(3):
        img = np.asarray(Image.open(W / "diag" / tag / f"l_{v}_L{k}.png").convert("RGB")).astype(float)
        ids = decode(str(W / "diag" / tag / f"l_{v}_L{k}_id.png"), bits)
        flat = ids.ravel()
        pix = img.reshape(-1, 3)
        for idv in np.unique(flat):
            c = cls.get(int(idv)) if int(idv) >= 0 else None
            if c is None or c[1] != k:
                continue
            sel = pix[flat == idv]
            a = acc.setdefault((c[0], k, c[2]), [0, np.zeros(3)])
            a[0] += len(sel)
            a[1] += sel.sum(axis=0)
rows = []
for part in ("wall", "roof"):
    for bid in sorted(meta):
        L = [acc.get((bid, k, part)) for k in range(3)]
        if not all(L) or min(x[0] for x in L) < minpx:
            continue
        lm = [luma(x[1] / x[0]) for x in L]
        rows.append({"id": bid, "part": part, "px": [x[0] for x in L], "luma": [round(x, 1) for x in lm], "r10": round(lm[1] / lm[0], 3), "r20": round(lm[2] / lm[0], 3),
                     "district": meta[bid]["district"], "plaster": meta[bid]["plaster"], "wood": meta[bid]["wood"]})
for part in ("wall", "roof"):
    R = [r for r in rows if r["part"] == part]
    if not R:
        continue
    r10 = np.array([r["r10"] for r in R])
    r20 = np.array([r["r20"] for r in R])
    print(f"== {'壁' if part == 'wall' else '屋根'}（比較できる建物 {len(R)} 棟・各 LOD ≥ {minpx} px）")
    print(f"   L1/L0  中央値 {np.median(r10):.2f}  p10 {np.percentile(r10, 10):.2f}  p90 {np.percentile(r10, 90):.2f}  範囲 {r10.min():.2f}–{r10.max():.2f}")
    print(f"   L2/L0  中央値 {np.median(r20):.2f}  p10 {np.percentile(r20, 10):.2f}  p90 {np.percentile(r20, 90):.2f}  範囲 {r20.min():.2f}–{r20.max():.2f}")
    inb = sum(1 for r in R if 0.8 <= r["r10"] <= 1.25 and 0.8 <= r["r20"] <= 1.25)
    print(f"   0.80–1.25 に収まる建物 {inb}／{len(R)}")
    for r in sorted(R, key=lambda r: -max(abs(np.log(r["r10"])), abs(np.log(r["r20"]))))[:5]:
        print(f"     外れ値 {r['id']} {r['district']:16s} L1/L0 {r['r10']:.2f}  L2/L0 {r['r20']:.2f}  luma {r['luma']}  px {r['px']}")
if out:
    Path(out).write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
