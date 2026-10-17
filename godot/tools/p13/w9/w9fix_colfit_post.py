"""P13 W9 FIX：w9fix_colfit.gd の結果 → 建物ごとの碰撞箱データ（collision_fit.json）。

    python godot/tools/p13/w9/w9fix_colfit_post.py <colfit.json> <colfit_archoff.json> [--out=<json>]

対象＝W9R2 の外形（overlay 有効）で出た理由のうち、Kit だけの外観（overlay 無効＝W9R2 以前）では出ない理由があるもの
（＝W9R2 が持ち込んだ不一致）。Kit の時から同じ理由の棟は PRE-EXISTING として触らない。

整形の規則（すべて決まった閾値・数値は下の定数）：
  P1 幅 ≤ 0.7 m・奥行き > 1.0 m の一段目の細長い箱で、元の箱の左右の面に接していないもの＝『柱の影』
     （正面の柱に ray が当たり、その後ろが壁扱いになったもの）。
       その x 範囲に庇柱の碰撞（overlay の Posts）があれば捨てる（二重にしない）。無ければ前端 0.5 m だけ残す（柱そのもの）。
     元の箱の左右の面に接しているもの＝袖壁・塀 → 残す。
  P2 低い物の箱（tier 0）が Posts の箱と床面積の半分以上重なれば捨てる（二重にしない・床や台が柱の足元に触れるだけなら残す）。
  P3 低い物の箱どうし：z 範囲がほぼ同じで x の隙間 ≤ 0.7 m（柱）なら 1 つに、x 範囲がほぼ同じで z が接していれば 1 つに。
  P4 二段目の箱（tier 2）どうし：片方の軸の範囲がほぼ同じで、もう片方の隙間 ≤ 0.5 m（棟の線）なら 1 つに（上面は低い方）。
  P5 一段目どうしの z の隙間 ≤ 0.5 m（x が重なる）は、上面の低い方の箱を伸ばして塞ぐ。
  tier 3（庇の板）・tier 4（屋根の中の詰め物）はそのまま通す。
  tier 5（TARGETED）：最終驗收の相機確認で再現した垂れ壁・袖壁（MKT_030／MXC_007 だけ・採寸値）を足す。
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]          # godot/
POSTS_JSON = ROOT / "assets/village_v2/w9r2_arch/src/modules_blender.json"
DEFAULT_OUT = ROOT / "assets/village_v2/w9r2_arch/src/collision_fit.json"
POST_PAD = 0.03                                      # build_w9r2.gd の L.POST_PAD と同じ

CATS = {"箱が屋根より": "roof_above", "見える壁が箱の上": "wall_above", "外形が": "shape", "低い物": "low",
        "面が見た目より": "face_in", "面の見た目が": "face_out", "二段目": "t2"}


def cats(reasons):
    return {v for r in reasons for k, v in CATS.items() if k in r}


def overlap(a0, a1, b0, b1):
    return min(a1, b1) - max(a0, b0)


def post_boxes(posts):
    out = []
    for p in posts:
        h = max(p["w"] / 2 + POST_PAD, 0.125)
        out.append((p["x"] - h, p["x"] + h, p["z"] - h, p["z"] + h))
    return out


def shape(boxes, orig, posts, log):
    pb = post_boxes(posts)
    res = []
    for b in boxes:
        b = dict(b)
        w = b["x1"] - b["x0"]
        d = b["z1"] - b["z0"]
        if b["tier"] == 1 and w <= 0.7 and d > 1.0:
            touches = abs(b["x0"] - orig["x0"]) <= 0.05 or abs(b["x1"] - orig["x1"]) <= 0.05
            if not touches:
                if any(overlap(b["x0"] - 0.1, b["x1"] + 0.1, p[0], p[1]) > 0 for p in pb):
                    log.append("P1 柱の影を捨てた（Posts あり）x %.2f..%.2f" % (b["x0"], b["x1"]))
                    continue
                b["z0"] = round(b["z1"] - 0.5, 2)
                log.append("P1 柱の影 → 前端 0.5 m の柱だけ x %.2f..%.2f" % (b["x0"], b["x1"]))
        # 重なりが箱の床面積の半分以上の時だけ（＝柱そのものを拾った箱）。床・見世の台が柱の足元に触れるだけなら残す
        # （W9 FIX 最終驗收：MXC_007 の見世の床・台が 3 本の庇柱に触れて丸ごと捨てられた）
        if b["tier"] == 0 and sum(max(0.0, overlap(b["x0"], b["x1"], p[0], p[1])) * max(0.0, overlap(b["z0"], b["z1"], p[2], p[3])) for p in pb) >= 0.5 * w * d:
            log.append("P2 低い物の箱を捨てた（Posts と重複）x %.2f..%.2f" % (b["x0"], b["x1"]))
            continue
        res.append(b)
    # P3／P4：同じ tier の箱を 1 つにまとめる
    for tier, gap, why in ((0, 0.7, "P3"), (2, 0.5, "P4")):
        changed = True
        while changed:
            changed = False
            ts = [b for b in res if b["tier"] == tier]
            for i in range(len(ts)):
                for j in range(i + 1, len(ts)):
                    a, c = ts[i], ts[j]
                    same_z = abs(a["z0"] - c["z0"]) <= 0.1 and abs(a["z1"] - c["z1"]) <= 0.1
                    same_x = abs(a["x0"] - c["x0"]) <= 0.15 and abs(a["x1"] - c["x1"]) <= 0.15
                    gx = max(a["x0"], c["x0"]) - min(a["x1"], c["x1"])
                    gz = max(a["z0"], c["z0"]) - min(a["z1"], c["z1"])
                    # tier 0 は上面が近い（±0.15）ものだけ（床 0.3 と台 1.0 をまとめると、床の上に 1.0 m の見えない壁ができる）
                    same_top = tier != 0 or abs(a["y1"] - c["y1"]) <= 0.15
                    if same_top and ((same_z and gx <= gap) or (same_x and gz <= gap)):
                        m = {"x0": min(a["x0"], c["x0"]), "x1": max(a["x1"], c["x1"]), "z0": min(a["z0"], c["z0"]),
                             "z1": max(a["z1"], c["z1"]), "y0": min(a["y0"], c["y0"]), "y1": min(a["y1"], c["y1"]), "tier": tier}
                        if tier == 0:
                            m["y1"] = max(a["y1"], c["y1"])
                        res.remove(a)
                        res.remove(c)
                        res.append(m)
                        log.append("%s まとめた x %.2f..%.2f z %.2f..%.2f" % (why, m["x0"], m["x1"], m["z0"], m["z1"]))
                        changed = True
                        break
                if changed:
                    break
    # P5：一段目どうしの z の隙間（各箱の『すぐ後ろ』の箱との隙間だけ。既に別の箱が埋めている所は触らない）
    t1 = sorted([b for b in res if b["tier"] == 1], key=lambda b: b["z0"])
    for a in t1:
        cands = [c for c in t1 if c is not a and overlap(a["x0"], a["x1"], c["x0"], c["x1"]) > 0.2 and c["z0"] - a["z1"] > -1e-6]
        if not cands:
            continue
        c = min(cands, key=lambda c: c["z0"] - a["z1"])
        g = c["z0"] - a["z1"]
        if 0.0 < g <= 0.5:
            if c["y1"] <= a["y1"]:
                c["z0"] = a["z1"]
            else:
                a["z1"] = c["z0"]
            log.append("P5 z の隙間 %.2f m を塞いだ" % g)
    return res


# tier 5：W9 FIX 最終驗收（使用者 2026-10-17「Freeze-Oriented Closure」2. の『的を絞った修正 1 回』）。
# 実プレイ TPS 相機確認（tools/p13/w9/w9fix_cam_review.gd）で再現した 2 棟：開いた見世の上の『垂れ壁』と、MXC_007 の見世の左右の袖壁に
# 碰撞が無く、相機の腕が見える壁を抜けて見世の中（屋根の下）へ入り、玩家が梁・壁の陰になる（0.73–1.28 s 連続）。
# 壁の範囲は見た目への水平 ray で採寸（work/w9_collision_fix/cam_review/measure_hangwall.log：開口の上の壁が立面から 0.30 m 以内に
# 当たる高さ）。袖壁の上端は屋根の勾配に沿って 4 段（各段はその範囲の見た目の上端の最小値）。他の棟・生成器の規則は変えない。
TARGETED = {
    "B_P_MKT_030": [
        {"x0": -1.30, "x1": 2.10, "z0": 5.30, "z1": 5.46, "y0": 2.00, "y1": 2.75, "tier": 5},     # 正面の垂れ壁 y 2.00–2.75（t3 の板の下端まで）
    ],
    "B_P_MXC_007": [
        {"x0": -3.95, "x1": 3.95, "z0": 5.30, "z1": 5.46, "y0": 2.40, "y1": 2.70, "tier": 5},     # 正面の垂れ壁 y 2.40–2.70
        {"x0": -3.95, "x1": -3.80, "z0": 1.90, "z1": 2.90, "y0": -0.38, "y1": 3.30, "tier": 5},   # 左の袖壁（勾配 4 段）
        {"x0": -3.95, "x1": -3.80, "z0": 2.90, "z1": 3.90, "y0": -0.38, "y1": 3.05, "tier": 5},
        {"x0": -3.95, "x1": -3.80, "z0": 3.90, "z1": 4.90, "y0": -0.38, "y1": 2.80, "tier": 5},
        {"x0": -3.95, "x1": -3.80, "z0": 4.90, "z1": 5.46, "y0": -0.38, "y1": 2.70, "tier": 5},
        {"x0": 3.80, "x1": 3.95, "z0": 1.90, "z1": 2.90, "y0": -0.38, "y1": 3.30, "tier": 5},     # 右の袖壁
        {"x0": 3.80, "x1": 3.95, "z0": 2.90, "z1": 3.90, "y0": -0.38, "y1": 3.05, "tier": 5},
        {"x0": 3.80, "x1": 3.95, "z0": 3.90, "z1": 4.90, "y0": -0.38, "y1": 2.80, "tier": 5},
        {"x0": 3.80, "x1": 3.95, "z0": 4.90, "z1": 5.46, "y0": -0.38, "y1": 2.70, "tier": 5},
    ],
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = DEFAULT_OUT
    for a in sys.argv[1:]:
        if a.startswith("--out="):
            out = Path(a[6:])
    fit = json.loads(Path(args[0]).read_text(encoding="utf-8"))
    kit = json.loads(Path(args[1]).read_text(encoding="utf-8"))
    posts_all = json.loads(POSTS_JSON.read_text(encoding="utf-8")).get("posts", {})
    data = {"_note": "P13 W9 FIX：W9R2 で外形が変わった建物の碰撞箱（建物 body の局部座標・m）。"
                     "tools/p13/w9/w9fix_colfit.gd（見た目から導出）→ w9fix_colfit_post.py（整形）が産生。"
                     "build_w9r2.gd が <id>/Shell（StaticBody3D・body と同じ layer／mask）を作り、arch_w9r2.gd が overlay 有効の間だけ "
                     "body の元の箱と入れ替える。", "buildings": {}}
    for bid in sorted(fit):
        w9, k = fit[bid], kit[bid]
        new = cats(w9["reasons"]) - cats(k["reasons"])
        if not w9["apply"] or not new:
            continue
        log = []
        boxes = shape(w9["fit"], w9["orig"], posts_all.get(bid, []), log)
        if bid in TARGETED:
            boxes += [dict(b) for b in TARGETED[bid]]
            log.append("T5 的を絞った修正（垂れ壁・袖壁）%d 箱" % len(TARGETED[bid]))
        boxes.sort(key=lambda b: (b["tier"], b["z0"], b["x0"]))
        data["buildings"][bid] = {
            "reasons_w9": w9["reasons"], "reasons_kit": k["reasons"], "new": sorted(new),
            "orig": {kk: round(v, 3) for kk, v in w9["orig"].items()},
            "boxes": [{kk: (round(v, 2) if isinstance(v, float) else v) for kk, v in b.items()} for b in boxes],
            "post_rules": log,
        }
        print(bid, sorted(new), len(boxes), "boxes", "|", "; ".join(log))
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("wrote", out, len(data["buildings"]), "buildings")


if __name__ == "__main__":
    main()
