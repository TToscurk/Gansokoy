#!/usr/bin/env python3
"""Wind V1 取證分析：讀 wind_capture 的 manifest，算「每幀動量」、產 GIF 與總表。

用法：
  python tools/wind/wind_analyze.py --dir C:/Users/.../wind_v1/final_village \
      --out C:/Users/.../wind_v1/out_village [--gif-views market_noren,meadow_a]

量的是相鄰兩幀的平均絕對差（0–255）。同一台相機、同一個風時鐘步進，
所以「breeze 的動量 > off 的動量」代表 shader 真的在動；off 那組是
場景本身的殘餘動畫（水、雲、LOD 抖動）＝視覺基線。
"""
import argparse
import glob
import json
import os
from collections import defaultdict

import numpy as np
from PIL import Image


def load_manifest(d):
    with open(os.path.join(d, "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def motion(files):
    arrs = [np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) for p in files]
    if len(arrs) < 2:
        return 0.0, 0.0, None
    diffs = [np.abs(arrs[i + 1] - arrs[i]) for i in range(len(arrs) - 1)]
    m = float(np.mean([d.mean() for d in diffs]))
    mx = float(np.max([d.mean() for d in diffs]))
    return m, mx, diffs


def make_gif(files, out, width=480, ms=110):
    imgs = [Image.open(p).convert("RGB") for p in files]
    w, h = imgs[0].size
    h2 = int(round(h * width / w))
    imgs = [im.resize((width, h2), Image.LANCZOS) for im in imgs]
    imgs[0].save(out, save_all=True, append_images=imgs[1:], duration=ms, loop=0, optimize=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--gif-views", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    man = load_manifest(args.dir)
    groups = defaultdict(list)
    for s in man["shots"]:
        groups[s["key"]].append(s)
    rows = []
    for key, shots in sorted(groups.items()):
        shots.sort(key=lambda s: s["frame"])
        files = [s["file"] for s in shots]
        m, mx, diffs = motion(files)
        rows.append({
            "key": key,
            "frames": len(files),
            "motion": round(m, 4),
            "motion_max": round(mx, 4),
            "strength": round(float(np.mean([s["strength"] for s in shots])), 3),
            "gust": round(float(np.mean([s["gust"] for s in shots])), 3),
        })
        if diffs is not None:
            amp = np.clip(np.mean(diffs, axis=0) * 14, 0, 255).astype(np.uint8)
            Image.fromarray(amp).save(os.path.join(args.out, f"diff_{key}.jpg"), quality=88)
    # 每個 view 的 off 基線 → 動量比
    base = {}
    for r in rows:
        if r["key"].endswith("_off"):
            base[r["key"][:-4]] = r["motion"]
    for r in rows:
        view = r["key"].rsplit("_", 1)[0]
        b = base.get(view)
        r["off_motion"] = b
        r["ratio"] = round(r["motion"] / b, 2) if b and b > 0 else None
    summary = {"scene": man["scene"], "rows": rows}
    with open(os.path.join(args.out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    print(f"{'key':34s} {'frames':>6s} {'motion':>7s} {'max':>7s} {'off':>7s} {'ratio':>6s}")
    for r in rows:
        off = "-" if r["off_motion"] is None else f"{r['off_motion']:.3f}"
        ratio = "-" if r["ratio"] is None else f"{r['ratio']:.2f}"
        print(f"{r['key']:34s} {r['frames']:6d} {r['motion']:7.3f} {r['motion_max']:7.3f} {off:>7s} {ratio:>6s}")
    if args.gif_views:
        for v in args.gif_views.split(","):
            for r in rows:
                if r["key"] == f"{v}_breeze" or r["key"] == f"{v}_gust":
                    files = sorted(glob.glob(os.path.join(args.dir, f"{r['key']}_*.png")))
                    g = make_gif(files, os.path.join(args.out, f"{r['key']}.gif"))
                    print("gif ->", g)


if __name__ == "__main__":
    main()
