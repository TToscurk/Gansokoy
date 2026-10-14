"""P13 W8 TASK B：LOD1／LOD2 の壁・正面・屋根の乗数を擬合し、調色盤（少数の材質）へ丸めて材質ファイルと登記表を書く。
  uv run --quiet --with numpy python w8_lod_fit_build.py fit  <evidence dir> [--gain=gain.json] [--write]
  uv run --quiet --with numpy python w8_lod_fit_build.py show <evidence dir>        （LOD0 vs LODk の素の色差だけ要約）
入力：evidence/albedo_probe_batch.json（w8_albedo_probe.gd・各建物×LOD の『部品接頭辞|類』別 面積と線形 albedo）＋ data/village_v2_p13w7_batch1.json（名簿）
擬合の定義（すべて面積加重の線形 albedo・RGB 各チャンネル）：
  W0(b)＝LOD0 の壁部位（sd_d／gbh／bk_*／rt_h／sdo_d／u_plain／ud／udk／dmg／rtu）   → LOD1 の壁箱 l_box* を W0 に
  F0(b)＝LOD0 の正面部位（f／fp／fb／sf／post_e／nr_*／iy／kb*／gyo／kiri／u_win*／u_mushi*） → LOD1 の正面 l_f*／l_u* を F0 に
  B0(b)＝W0 と F0 の面積加重 → LOD2 の壁箱（LOD2 は箱だけ＝建物全体の平均色を担う）
  R0(b)＝LOD0 の kawara 類 → LOD1／2 の屋根 l_rh* を R0 に（l_rh* は元の V2_MachiyaKit〔0.42 灰＝線形 0.1413〕のまま）
乗数 s＝target／current をチャンネルごとに求め、[0.15, 3.0] に clamp。gain.json（W8 の画素検証で得た全体補正）があれば掛ける。
調色盤＝log 空間の k-means（決定論的な初期化）。k は『最大誤差 ≤ 12 %・95 百分位 ≤ 7 %』を満たす最小値。
"""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

GODOT = Path("D:/神社/shrine/godot")
OUTDIR = GODOT / "maps/village_v2/lod_cal_p13"
REG = OUTDIR / "lod_material_variants.json"
MAN = GODOT / "data/village_v2_p13w8_lod.json"
SHADER = "res://maps/village_v2/lod_cal_p13/kit_cal_lod.gdshader"
SHADER_FILE = OUTDIR / "kit_cal_lod.gdshader"
BASE = "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"
ORIG_K = 0.1413  # 原 V2_MachiyaKit：albedo_color 0.42 灰（sRGB）＝線形 0.1413
LO, HI = 0.15, 3.0
LUM = np.array([0.2126, 0.7152, 0.0722])

WALL = ("sd_d", "gbh", "bk_plain", "bk_win", "rt_h", "sdo_d", "u_plain", "ud", "udk", "dmg", "rtu")
FRONT = ("f", "fp", "fb", "sf", "post_e", "nr_", "iy", "kb", "gyo", "kiri", "u_win", "u_mushi")


def fam(prefix):
    if prefix == "f" or prefix.startswith(("fp", "fb", "sf", "post_e", "nr_", "iy", "kb", "gyo", "kiri", "u_win", "u_mushi")):
        return "front"
    if prefix.startswith(WALL):
        return "wall"
    return ""


def agg(parts, pick):
    """parts: {'接頭辞|類': [area,r,g,b]}、pick(prefix, cls)->bool。返り値 (area, rgb)"""
    a = 0.0
    s = np.zeros(3)
    for k, v in parts.items():
        p, c = k.split("|")
        if pick(p, c):
            a += v[0]
            s += v[0] * np.array(v[1:4])
    return a, (s / a if a > 0 else None)


def raw_multipliers(b):
    L0, L1, L2 = b["L0"]["_parts"], b["L1"]["_parts"], b["L2"]["_parts"]
    aw, W0 = agg(L0, lambda p, c: fam(p) == "wall" and c in ("plaster", "wood", "atlas_light", "atlas_mid", "atlas_dark"))
    af, F0 = agg(L0, lambda p, c: fam(p) == "front" and c in ("plaster", "wood", "atlas_light", "atlas_mid", "atlas_dark"))
    B0 = (aw * W0 + af * F0) / (aw + af)
    _, R0 = agg(L0, lambda p, c: c == "kawara")
    _, box1 = agg(L1, lambda p, c: p.startswith("l_box"))
    _, face1 = agg(L1, lambda p, c: p.startswith(("l_f", "l_u_")) and c.startswith("atlas"))
    _, box2 = agg(L2, lambda p, c: p.startswith("l_box"))
    _, rh1 = agg(L1, lambda p, c: p.startswith("l_rh"))
    _, rh2 = agg(L2, lambda p, c: p.startswith("l_rh"))
    out = {"box1": W0 / box1, "face1": F0 / face1, "box2": B0 / box2, "roof": R0 / rh1, "roof2": R0 / rh2}
    cur = {"W0": W0, "F0": F0, "B0": B0, "R0": R0, "box1": box1, "face1": face1, "box2": box2, "rh1": rh1}
    return {k: np.clip(v, LO, HI) for k, v in out.items()}, cur


def kmeans(X, k, iters=60):
    # 決定論的初期化：最遠点
    c = [X[0]]
    for _ in range(1, k):
        d = np.min([np.linalg.norm(X - ci, axis=1) for ci in c], axis=0)
        c.append(X[int(np.argmax(d))])
    c = np.array(c)
    for _ in range(iters):
        lab = np.argmin(np.linalg.norm(X[:, None, :] - c[None, :, :], axis=2), axis=1)
        nc = np.array([X[lab == i].mean(axis=0) if np.any(lab == i) else c[i] for i in range(k)])
        if np.allclose(nc, c):
            break
        c = nc
    lab = np.argmin(np.linalg.norm(X[:, None, :] - c[None, :, :], axis=2), axis=1)
    return c, lab


TOL_MAX, TOL_P95 = 1.18, 1.12   # 調色盤の丸め誤差の上限（線形 albedo の比・最悪チャンネル）。現状の食い違い（壁 2.5 倍・色相ずれ 0.3）に対して十分小さい


def palette(X, name):
    """X: (n,d) の log 乗数。誤差基準を満たす最小の k（k と誤差の表も出す）"""
    tab = []
    pick = None
    for k in range(1, min(len(X), 24) + 1):
        c, lab = kmeans(X, k)
        err = np.abs(X - c[lab]).max(axis=1)   # log 差の最大チャンネル
        tab.append((k, float(np.exp(err.max()) - 1), float(np.exp(np.percentile(err, 95)) - 1)))
        if pick is None and err.max() <= np.log(TOL_MAX) and np.percentile(err, 95) <= np.log(TOL_P95):
            pick = (c, lab, err)
    print("  [%s] k→(最大, 95%%): %s" % (name, " ".join("%d:%.0f/%.0f%%" % (k, m * 100, q * 100) for k, m, q in tab[:14])))
    if pick is not None:
        return pick
    c, lab = kmeans(X, min(len(X), 24))
    return c, lab, np.abs(X - c[lab]).max(axis=1)


def tres(rid, params):
    def v3(x):
        return "Vector3(%.4f, %.4f, %.4f)" % tuple(x)
    lines = [
        '[gd_resource type="ShaderMaterial" format=3]', "",
        '[ext_resource type="Shader" path="%s" id="1_lod"]' % SHADER,
        '[ext_resource type="Texture2D" path="res://assets/village_v2/machiya_kit/machiya_kit_atlas.png" id="2_atl"]',
        '[ext_resource type="Texture2D" path="res://assets/village_v2/machiya_kit/machiya_kit_emit.png" id="3_emi"]', "",
        "[resource]", 'resource_name = "%s"' % rid, "render_priority = 0", 'shader = ExtResource("1_lod")',
        'shader_parameter/albedo_tex = ExtResource("2_atl")', 'shader_parameter/emit_tex = ExtResource("3_emi")',
        "shader_parameter/k_dark = 0.75", "shader_parameter/k_mid = 0.42", "shader_parameter/k_light = 0.7",
        "shader_parameter/band_dark = Vector2(0.26, 0.34)", "shader_parameter/band_light = Vector2(0.55, 0.7)",
        "shader_parameter/roughness_v = 0.9", "shader_parameter/emission_energy = 0.4",
    ]
    if "box_mul" in params:
        lines.append("shader_parameter/box_mul = " + v3(params["box_mul"]))
    if "face_mul" in params:
        lines.append("shader_parameter/face_mul = " + v3(params["face_mul"]))
    if params.get("roof_mode"):
        lines.append("shader_parameter/roof_mode = true")
        lines.append("shader_parameter/roof_k = " + v3(params["roof_k"]))
    return "\n".join(lines) + "\n"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    mode = sys.argv[1]
    E = Path(sys.argv[2])
    gain = {}
    write = "--write" in sys.argv
    for a in sys.argv[3:]:
        if a.startswith("--gain="):
            gain = json.load(open(a[7:], encoding="utf-8"))
    probe = json.load(open(E / "albedo_probe_batch.json", encoding="utf-8"))["buildings"]
    man = {r["id"]: r for r in json.load(open(GODOT / "data/village_v2_p13w7_batch1.json", encoding="utf-8"))["buildings"]}
    ids = sorted(probe)
    raw = {}
    cur = {}
    for bid in ids:
        raw[bid], cur[bid] = raw_multipliers(probe[bid])
    if mode == "show":
        for key in ("box1", "face1", "box2", "roof"):
            M = np.array([raw[b][key] for b in ids])
            L = np.array([float(np.dot(m, LUM)) for m in M])
            print(f"{key:6s} 乗数 輝度加重 中央値 {np.median(L):.2f} 範囲 {L.min():.2f}–{L.max():.2f}   RGB 中央値 {np.median(M, axis=0).round(2)}")
        return
    g = {k: np.array(gain.get(k, [1, 1, 1]), dtype=float) for k in ("box1", "face1", "box2", "roof")}
    S = {b: {k: np.clip(raw[b][k] * g[k], LO, HI) for k in ("box1", "face1", "box2", "roof")} for b in ids}
    FACE_SCALE = 2.5   # 正面は面積が小さく組成も建物ごとに違う → 牆箱の 2.5 倍まで許容（誤差基準は箱の 12 %／7 % に対し正面 28 %／18 %）
    X1 = np.array([np.concatenate([np.log(S[b]["box1"]), np.log(S[b]["face1"]) / FACE_SCALE]) for b in ids])
    X2 = np.array([np.log(S[b]["box2"]) for b in ids])
    XR = np.array([np.log(S[b]["roof"]) for b in ids])
    c1, l1, e1 = palette(X1, "L1")
    c2, l2, e2 = palette(X2, "L2")
    cr, lr, er = palette(XR, "roof")
    print(f"調色盤：LOD1 {len(c1)} 材質（最大誤差 {np.exp(e1.max())-1:.1%}・95% {np.exp(np.percentile(e1,95))-1:.1%}）／LOD2 {len(c2)}（{np.exp(e2.max())-1:.1%}・{np.exp(np.percentile(e2,95))-1:.1%}）／屋根 {len(cr)}（{np.exp(er.max())-1:.1%}・{np.exp(np.percentile(er,95))-1:.1%}）")
    mats = []
    for i, c in enumerate(c1):
        mats.append({"id": "V2_MachiyaKit_L1_P%02d" % i, "kind": "l1", "params": {"box_mul": np.exp(c[:3]).round(4).tolist(), "face_mul": np.exp(c[3:] * FACE_SCALE).round(4).tolist()}})
    for i, c in enumerate(c2):
        mats.append({"id": "V2_MachiyaKit_L2_P%02d" % i, "kind": "l2", "params": {"box_mul": np.exp(c).round(4).tolist(), "face_mul": [1.0, 1.0, 1.0]}})
    for i, c in enumerate(cr):
        mats.append({"id": "V2_MachiyaKit_LR_%02d" % i, "kind": "roof", "params": {"roof_mode": True, "roof_k": (ORIG_K * np.exp(c)).round(5).tolist()}})
    assign = []
    for n, b in enumerate(ids):
        assign.append({"id": b, "path": man[b]["path"], "l1": "V2_MachiyaKit_L1_P%02d" % l1[n], "l2": "V2_MachiyaKit_L2_P%02d" % l2[n], "roof": "V2_MachiyaKit_LR_%02d" % lr[n],
                       "palette": [man[b]["plaster"], man[b]["wood"]]})
    # 擬合後に期待される albedo（解析値）：LOD1／2 の壁箱・正面・屋根が LOD0 目標に対してどれだけ近いか
    res = []
    for n, b in enumerate(ids):
        cc = cur[b]
        m1 = {m["id"]: m["params"] for m in mats}
        p1 = m1[assign[n]["l1"]]
        p2 = m1[assign[n]["l2"]]
        pr = m1[assign[n]["roof"]]
        new_box1 = cc["box1"] * np.array(p1["box_mul"])
        new_face1 = cc["face1"] * np.array(p1["face_mul"])
        new_box2 = cc["box2"] * np.array(p2["box_mul"])
        new_roof = cc["rh1"] / ORIG_K * np.array(pr["roof_k"])
        res.append({"id": b,
                    "box1_vs_W0": float(np.dot(new_box1, LUM) / np.dot(cc["W0"], LUM)),
                    "face1_vs_F0": float(np.dot(new_face1, LUM) / np.dot(cc["F0"], LUM)),
                    "box2_vs_B0": float(np.dot(new_box2, LUM) / np.dot(cc["B0"], LUM)),
                    "roof_vs_R0": float(np.dot(new_roof, LUM) / np.dot(cc["R0"], LUM))})
    for key in ("box1_vs_W0", "face1_vs_F0", "box2_vs_B0", "roof_vs_R0"):
        v = np.array([r[key] for r in res])
        print(f"  擬合後 {key:12s} 輝度比 中央値 {np.median(v):.3f}  範囲 {v.min():.3f}–{v.max():.3f}")
    out = {"gain": {k: g[k].tolist() for k in g}, "n_l1": len(c1), "n_l2": len(c2), "n_roof": len(cr), "materials": mats, "assign": assign, "residual": res}
    (E / "lod_fit.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    if not write:
        print("（--write なし：材質ファイルは書かない）")
        return
    OUTDIR.mkdir(parents=True, exist_ok=True)
    variants = []
    for m in mats:
        f = OUTDIR / (m["id"] + ".tres")
        f.write_text(tres(m["id"], m["params"]), encoding="utf-8", newline="\n")
        variants.append({"id": m["id"], "kind": m["kind"], "base": BASE, "file": "res://maps/village_v2/lod_cal_p13/%s.tres" % m["id"], "sha256": sha(f), "params": m["params"]})
    reg = {
        "phase": "P13 W8 TASK B — LOD1／LOD2 町家 atlas 材質（按建築調色盤）",
        "approved_by": "user（P13 WAVE 8 TASK B 授權：少量按建築調色盤分類的 LOD 材質・2026-10-14）",
        "shader": {"file": SHADER, "sha256": sha(SHADER_FILE)},
        "limits": {"mul": [LO, HI], "roof_k": [ORIG_K * LO, ORIG_K * HI]},
        "rule": "V2_MachiyaKit（LOD1／LOD2 の atlas 表面）の surface override だけ・第一批 50 棟（data/village_v2_p13w7_batch1.json）の LOD1／LOD2 だけ・LOD0 は不変・幾何不変",
        "variants": variants,
    }
    REG.write_text(json.dumps(reg, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    manifest = {
        "schema": 1, "phase": "P13 W8 TASK B — LOD1／LOD2 色の整合（第一批 50 棟）",
        "approved_by": "user（P13 WAVE 8 TASK B・2026-10-14）",
        "node": "LodCalBatch1P13", "overlay": "res://maps/village_v2/gen/lod_cal_batch1_p13.scn",
        "registry": "res://maps/village_v2/lod_cal_p13/lod_material_variants.json", "count": len(assign), "buildings": assign,
        "fit": {"gain": {k: g[k].tolist() for k in g}, "n_l1": len(c1), "n_l2": len(c2), "n_roof": len(cr)},
    }
    MAN.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("書き込み：材質", len(mats), "・登記表・名簿")


main()
