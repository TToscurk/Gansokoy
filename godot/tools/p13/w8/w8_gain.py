"""P13 W8 TASK B：画素実測（w8_lodcolor.py の summary）から、LOD1／LOD2 材質の全体補正 gain（線形 albedo の RGB 乗数）を作る。
  uv run --quiet --with numpy python w8_gain.py <lod_color.json> <tag> <in gain.json|-> <out gain.json> [--roof-k=1.6]
LOD0 の壁・屋根の平均 RGB（sRGB）に LOD1／LOD2 を合わせる：gain ＝ 既存 gain × (LOD0/LODk)^2.2 （チャンネル別・線形近似）。
屋根は LOD1／2 の屋根系画素の一部しか l_rh（乗数を掛けた部分）でないので、指数を roof-k 倍する（既定 1.3）。色相は動かさず亮度だけ。
"""
import json
import sys

import numpy as np

src, tag, gin, gout = sys.argv[1:5]
roofk = 1.3
for a in sys.argv[5:]:
    if a.startswith("--roof-k="):
        roofk = float(a.split("=")[1])
d = json.load(open(src, encoding="utf-8"))["summary"]
wall = [np.array(x) for x in d[f"wall|batch|{tag}"]["rgb"]]
roof = [np.array(x) for x in d[f"roof|batch|{tag}"]["rgb"]]
g0 = json.load(open(gin, encoding="utf-8")) if gin != "-" else {k: [1, 1, 1] for k in ("box1", "face1", "box2", "roof")}
G = 2.2


def lum(c):
    return float(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])


upd = {
    "box1": (wall[0] / wall[1]) ** G,
    "face1": (wall[0] / wall[1]) ** G,
    "box2": (wall[0] / wall[2]) ** G,
    # 屋根は『亮度だけ』校正する：LOD0 の屋根系画素は暖色の木質簷口（rf の板・垂木）を含み、LOD1／2 は瓦だけ → 色相まで合わせると瓦が橙に染まる
    "roof": np.full(3, (lum(roof[0]) / lum(roof[1])) ** (G * roofk)),
}
out = {k: (np.array(g0[k]) * upd[k]).round(4).tolist() for k in upd}
json.dump(out, open(gout, "w"))
print(json.dumps(out))
