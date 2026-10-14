"""P13 Wave 6 ID パス解析ツール（唯読）。

  uv run --with pillow --with numpy python w6_idtool.py selftest <idpng> <idtable.json>
  uv run --with pillow --with numpy python w6_idtool.py top <idpng> <idtable.json> [N]

ID 画像：全 GeometryInstance3D を「一意な unshaded 色」に差し替えて撮ったもの。
  bits=5 → 各チャンネル = idpart*8+4、bits=6 → idpart*4+2。誤差を許して最近傍へ丸め、丸め残差が大きい画素は -1（＝ID 色ではない）。
"""
import json
import sys

import numpy as np
from PIL import Image


def load_table(path):
    d = json.load(open(path, encoding="utf-8"))
    return int(d["bits"]), {int(k): v for k, v in d["map"].items()}


def decode(img_path, bits):
    a = np.asarray(Image.open(img_path).convert("RGB")).astype(np.int32)
    sp = 8 if bits == 5 else 4
    half = sp // 2
    q = (a - half + sp // 2) // sp          # 最近傍
    q = np.clip(q, 0, (1 << bits) - 1)
    back = q * sp + half
    err = np.abs(a - back).max(axis=2)
    ids = (q[..., 0] << (2 * bits)) | (q[..., 1] << bits) | q[..., 2]
    tol = 1 if bits == 6 else 2
    ids = np.where(err <= tol, ids, -1)
    return ids, err


def main():
    cmd = sys.argv[1]
    img, table = sys.argv[2], sys.argv[3]
    bits, mp = load_table(table)
    ids, err = decode(img, bits)
    h, w = ids.shape
    valid = (ids >= 0)
    known = valid & np.isin(ids, np.fromiter(mp.keys(), dtype=np.int64))
    print(f"size {w}x{h}  valid-colour {valid.mean():.3f}  known-id {known.mean():.3f}  maxerr {err.max()}")
    if cmd in ("selftest", "top"):
        u, c = np.unique(ids[known], return_counts=True)
        order = np.argsort(-c)
        n = int(sys.argv[4]) if len(sys.argv) > 4 else 15
        for k in order[:n]:
            print(f"{c[k]:8d} {100*c[k]/ids.size:5.1f}%  {mp[int(u[k])]}")


if __name__ == "__main__":
    main()
