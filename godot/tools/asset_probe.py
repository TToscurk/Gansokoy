#!/usr/bin/env python3
"""資產落地量測 — 用 Blender MCP 直接讀 GLB 頂點，取代 AABB 推定。

為什麼存在
----------
Godot 的 AABB 只給軸對齊包圍盒。用它推「原點在哪」「可站立面多高」會錯：

  * 原點不一定在幾何中心。Meshy 匯出多半置中，但**盆樹的原點在底部**，
    照幾何中心擺會浮空。
  * AABB 底 != 可站立面。降台石5段的 AABB 高 0.85m，但實際行走落差只有
    0.59m（底部有凹陷、頂部有脊）。拿 AABB 高算 scale 會分子分母都錯。
  * 傾斜物件的 AABB 完全無法反映真實形狀（傾斜 BoxMesh 的坡向要算 basis）。

視覺判讀也不可靠：低解析度截圖交給 vision 判斷模型形狀，實測會得到
「中歐村鎮」「神廟基座」這類完全錯誤的描述。**形狀問題一律用頂點數字裁決。**

前置
----
Blender 開啟並啟動 BlenderMCP addon。面板顯示的 port 可能與實際監聽的不符，
本腳本會自動掃描 9875-9880。

用法
----
    python tools/asset_probe.py                     # 量預設清單
    python tools/asset_probe.py a.glb b.glb         # 量指定檔案
    python tools/asset_probe.py --profile a.glb     # 加掃剖面（階梯／斜坡用）
    python tools/asset_probe.py --json out.json     # 存成 JSON
"""

import argparse
import json
import socket
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent          # godot/
ASSETS = REPO / "assets"
PORT_RANGE = range(9875, 9881)

# 原點分類門檻（偏移量 / 模型高度）
CENTER_TOL = 0.02       # |ratio| < 此值 → 幾何中心
EDGE_TOL = 0.05         # |ratio - 0.5| < 此值 → 底部（或頂部）


def find_port(timeout=1.0):
    """BlenderMCP 面板顯示的 port 常與實際監聽不符，掃一遍。"""
    for p in PORT_RANGE:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        try:
            s.connect(("localhost", p))
            s.close()
            return p
        except OSError:
            continue
        finally:
            try:
                s.close()
            except OSError:
                pass
    return None


def bl(port, cmd, params=None, timeout=300):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(("localhost", port))
    s.sendall(json.dumps({"type": cmd, "params": params or {}}).encode())
    buf = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
        try:
            out = json.loads(buf.decode())
            s.close()
            return out
        except json.JSONDecodeError:
            continue
    s.close()
    return json.loads(buf.decode())


# Blender 端腳本。glTF 是 Y-up，匯入 Blender（Z-up）後高度軸是 Z。
_MEASURE = r'''
import bpy, json, os

paths = __PATHS__
want_profile = __PROFILE__
out = {}

for name, path in paths.items():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    if not os.path.exists(path):
        out[name] = {"error": "missing"}
        continue
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except Exception as e:
        out[name] = {"error": str(e)[:120]}
        continue
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    if not meshes:
        out[name] = {"error": "no mesh"}
        continue

    vs = []
    for o in meshes:
        vs += [o.matrix_world @ v.co for v in o.data.vertices]
    X = [v.x for v in vs]; Y = [v.y for v in vs]; Z = [v.z for v in vs]
    zlo, zhi = min(Z), max(Z)
    rec = {
        "nv": len(vs), "nmesh": len(meshes),
        "local_h": [round(zlo, 5), round(zhi, 5)],
        "footprint": [round(max(X) - min(X), 5), round(max(Y) - min(Y), 5)],
    }

    if want_profile and zhi > zlo:
        # 沿兩個水平軸各切 20 段，記錄每段的頂/底 —— 揭露階梯、斜坡、凹陷
        def scan(getter, lo, hi, n=20):
            rows = []
            for i in range(n):
                a = lo + (hi - lo) * i / n
                b = lo + (hi - lo) * (i + 1) / n
                sel = [v.z for v in vs if a <= getter(v) < b]
                if sel:
                    rows.append([round((a + b) / 2, 4),
                                 round(max(sel), 4), round(min(sel), 4)])
            return rows
        rec["profile_x"] = scan(lambda v: v.x, min(X), max(X))
        rec["profile_y"] = scan(lambda v: v.y, min(Y), max(Y))

    out[name] = rec

print("@@" + json.dumps(out, ensure_ascii=False))
'''


def measure(port, paths: dict, profile=False):
    code = (_MEASURE
            .replace("__PATHS__", json.dumps({k: str(v).replace("\\", "/")
                                              for k, v in paths.items()},
                                             ensure_ascii=False))
            .replace("__PROFILE__", "True" if profile else "False"))
    reply = bl(port, "execute_code", {"code": code})
    text = reply["result"]["result"]
    return json.loads(text[text.index("@@") + 2:].strip())


def classify(local_h):
    """原點相對模型的位置。回傳 (標籤, 偏移比例)。

    以「底部距原點多遠」為準，而非 AABB 中心的比例 —— 後者對低矮物件
    會誤判（0.1m 高的卵石底部差 8mm，比例上就成了 8%，但實務上那就是
    貼地的底部原點）。所以同時看絕對值與比例。
    """
    lo, hi = local_h
    h = hi - lo
    if h <= 0:
        return "退化", 0.0
    centre = (lo + hi) / 2
    ratio = centre / h          # 0 = 幾何中心；+0.5 = 原點在底部
    # 底部判定：底距原點的絕對距離小，或比例接近 +0.5
    if abs(lo) < 0.05 or abs(ratio - 0.5) < EDGE_TOL:
        return "底部", ratio
    if abs(ratio) < CENTER_TOL:
        return "幾何中心", ratio
    if abs(ratio + 0.5) < EDGE_TOL:
        return "頂部", ratio
    return f"底距原點 {lo:+.3f}", ratio


def place_y(local_h, scale, surface):
    """把物件底面放在 surface 高度時，節點 position.y 應該設多少。"""
    return surface - local_h[0] * scale


def walkable_span(rec, scale):
    """行走面的真實落差 —— 取剖面頂面的極值，而非 AABB 全高。

    階梯類資產必須用這個值算 scale，用 AABB 高會高估（含底部凹陷）。
    """
    prof = rec.get("profile_y") or rec.get("profile_x")
    if not prof:
        return None
    tops = [row[1] for row in prof]
    return (max(tops) - min(tops)) * scale


DEFAULT = {
    "收頭件大_厚":    ASSETS / "riverbank/收頭件大_厚.glb",
    "塊石疊砌牆一段":  ASSETS / "riverbank/塊石疊砌牆一段.glb",
    "親水階梯一組":    ASSETS / "riverbank/親水階梯一組.glb",
    "濱水平台一塊":    ASSETS / "riverbank/濱水平台一塊.glb",
    "降台石5段":      ASSETS / "riverbank/降台石5段.glb",
    "石造堰檻":       ASSETS / "riverbank/石造堰檻.glb",
    "堰分水閘門":      ASSETS / "riverbank/堰／小型分水閘門.glb",
    "田泵水口":       ASSETS / "riverbank/田泵水口.glb",
    "mooring_post":  ASSETS / "riverbank/mooring_post.glb",
    "水車":          ASSETS / "riverbank/水車.glb",
    "竹垣":          ASSETS / "landscape/竹垣.glb",
    "盆樹":          ASSETS / "landscape/盆樹.glb",
    "雜物草捆":       ASSETS / "market/雜物草捆.glb",
    "雜物堆木桶":      ASSETS / "market/雜物堆木桶.glb",
}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="GLB 路徑；省略則量預設清單")
    ap.add_argument("--profile", action="store_true",
                    help="加掃剖面，揭露階梯／斜坡的真實行走落差")
    ap.add_argument("--json", metavar="OUT", help="把結果寫成 JSON")
    args = ap.parse_args()

    port = find_port()
    if port is None:
        print(f"找不到 Blender MCP（掃過 {PORT_RANGE.start}-{PORT_RANGE.stop - 1}）。",
              file=sys.stderr)
        print("請確認 Blender 已開啟且 BlenderMCP addon 正在監聽。", file=sys.stderr)
        return 1
    print(f"Blender MCP: port {port}\n")

    paths = ({Path(f).stem: Path(f).resolve() for f in args.files}
             if args.files else DEFAULT)
    data = measure(port, paths, profile=args.profile)

    print(f"{'資產':<18} {'高度(本地)':>16} {'實高':>7} {'原點':>10} {'頂點數':>8}")
    print("-" * 68)
    exceptions = []
    for name, rec in data.items():
        if "error" in rec:
            print(f"{name:<18} {rec['error']}")
            continue
        label, ratio = classify(rec["local_h"])
        lo, hi = rec["local_h"]
        print(f"{name:<18} {lo:7.4f} → {hi:7.4f} {hi - lo:7.3f} {label:>10} {rec['nv']:8d}")
        if label != "幾何中心":
            exceptions.append((name, label, rec["local_h"]))

    if exceptions:
        print("\n★ 原點不在幾何中心 —— 擺放時 position.y 必須另外算：")
        for name, label, h in exceptions:
            print(f"   {name}：{label}")
        print(f"\n   底面貼齊 surface：y = surface - local_bottom * scale")
    else:
        print("\n所有資產原點都在幾何中心。")

    if args.profile:
        print("\n剖面（行走落差 vs AABB 全高）：")
        for name, rec in data.items():
            if "error" in rec or "profile_y" not in rec:
                continue
            lo, hi = rec["local_h"]
            span = walkable_span(rec, 1.0)
            print(f"  {name:<18} AABB {hi - lo:.4f}   行走落差 {span:.4f}"
                  f"   差 {(hi - lo) - span:+.4f}")
        print("  ← 差值大代表模型有底部凹陷或頂部凸脊，"
              "算 scale 要用行走落差不是 AABB 高")

    if args.json:
        Path(args.json).write_text(
            json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n已寫入 {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
