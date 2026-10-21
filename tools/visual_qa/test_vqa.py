"""P2 Visual QA 回歸（H1 十二案例＋H4 截圖可靠性／重現性／前後比較／定位／不誤判）。

  python tools/visual_qa/test_vqa.py [--keep] [--only=ok,post_float]

需要顯示（Godot 不得 headless）。fixture 與輸出都在 scratch，跑完預設刪除；不碰專案資產。
約 4 分鐘（14 次完整流程，每次約 12–16 秒）。
"""
import json
import os
import shutil
import subprocess
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import vqa  # noqa: E402
import vqa_analyze as VA  # noqa: E402

A = dict(a.lstrip("-").partition("=")[::2] for a in sys.argv[1:])
SCRATCH = os.environ.get("VQA_SCRATCH") or os.path.join(os.environ.get("LOCALAPPDATA", ROOT), "hermes", "cache", "scratch", "vqa_test")
FX = os.path.join(SCRATCH, "fx")
ONLY = set(A["only"].split(",")) if A.get("only") else None
results = []


def check(case, what, got, want, info=""):
    ok = got == want
    results.append((case, what, ok))
    print(f"{'ok ' if ok else 'BAD'} [{case}] {what}: got {got!r} want {want!r} {info}", flush=True)
    return ok


def near(case, what, got, want, tol, info=""):
    ok = got is not None and abs(got - want) <= tol
    results.append((case, what, ok))
    print(f"{'ok ' if ok else 'BAD'} [{case}] {what}: got {got} want {want}±{tol} {info}", flush=True)
    return ok


def run(name, *extra, fx=None, mode="full", profile="japanese_shrine", geo=True):
    fx = fx or name
    out = os.path.join(SCRATCH, "run_" + name)
    shutil.rmtree(out, ignore_errors=True)
    cmd = [sys.executable, os.path.join(HERE, "vqa.py"), f"--mode={mode}", f"--name={name}", f"--glb={FX}/{fx}.glb",
           f"--profile={profile}", f"--out={out}"]
    if geo:
        cmd += [f"--blend={FX}/{fx}.blend", f"--map={FX}/{fx}.arch.json"]
    t = time.time()
    p = subprocess.run(cmd + list(extra), capture_output=True, text=True, encoding="utf-8", errors="replace")
    rep = json.load(open(os.path.join(out, "report.json"), encoding="utf-8")) if os.path.exists(os.path.join(out, "report.json")) else None
    if rep is None:
        print(p.stdout[-2000:], p.stderr[-2000:])
    print(f"    {name}: exit {p.returncode}, {time.time() - t:.1f} s, {rep and rep['totals']}", flush=True)
    return rep, out, p.returncode


def row(rep, rid):
    for r in rep["results"]:
        if r["rule_id"] == rid:
            return r
    return None


def statuses(rep, prefix=""):
    return {r["rule_id"]: r["status"] for r in rep["results"] if r["rule_id"].startswith(prefix)}


def want(name):
    return ONLY is None or name in ONLY


def main():
    os.makedirs(FX, exist_ok=True)
    p = subprocess.run([vqa.BLENDER, "-b", "--factory-startup", "--python", os.path.join(HERE, "make_vqa_fixtures.py"),
                        "--", f"--out={FX}"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    check("setup", "fixtures", p.stdout.count("[VQA-FIX]"), 9)

    if want("ok"):  # 1 正常柱梁＋H4 截圖可靠性／重現性／不誤判
        rep, out, rc = run("ok")
        check("1-ok", "幾何全 PASS", rep["summary"]["geometry"]["FAIL"] + rep["summary"]["geometry"]["UNKNOWN"], 0)
        check("1-ok", "六視圖全部可靠", sorted(v for k, v in statuses(rep, "VIS_RELIABLE").items()), ["PASS"] * 6)
        check("1-ok", "正交剪影尺寸＝幾何（取景正確）", sorted(set(statuses(rep, "VIS_SCALE").values())), ["PASS"])
        check("1-ok", "正常日式屋頂不被誤判（無 FAIL/REVIEW）", (rep["totals"]["FAIL"], rep["totals"]["REVIEW"]), (0, 0))
        check("1-ok", "同場景重拍可重現", row(rep, "VIS_REPEAT:front")["status"], "PASS",
              str(row(rep, "VIS_REPEAT:front")["actual"]))
        check("1-ok", "對稱 IoU 高", row(rep, "VIS_SYMMETRY")["actual"]["iou"] > 0.98, True)
        check("1-ok", "exit 0", rc, 0)
        files = os.listdir(os.path.join(out, "capture"))
        check("1-ok", "六視圖＋標註分開保存", all(f"{v}.png" in files for v in vqa.SIX) and "views_sheet.jpg" in files, True)
        man = VA.load(os.path.join(out, "capture"))
        e = [x for x in man["images"] if x.get("view") == "front" and x["file"] == "front.png"][0]
        check("1-ok", "解析度記錄正確", man["resolution"], [1280, 720])
        # H4：全黑畫面、不在畫面內（合成影像，驗證可靠性判定本身）
        tmp = os.path.join(SCRATCH, "neg_capture")
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.copytree(os.path.join(out, "capture"), tmp)
        Image.new("RGB", (1280, 720)).save(os.path.join(tmp, "front.png"))
        r, _ = VA.reliability(tmp, man, e)
        check("H4", "全黑畫面 → UNKNOWN（BLACK_FRAME）", (r["status"], "BLACK_FRAME" in r["suggestion"]), ("UNKNOWN", True))
        shutil.copy(os.path.join(out, "capture", "front.png"), os.path.join(tmp, "front.png"))
        Image.new("RGB", (1280, 720)).save(os.path.join(tmp, "front_id.png"))
        r, _ = VA.reliability(tmp, man, e)
        check("H4", "建築不在畫面 → UNKNOWN（NOT_IN_FRAME）", (r["status"], "NOT_IN_FRAME" in r["suggestion"]), ("UNKNOWN", True))
        a = np.asarray(Image.open(os.path.join(out, "capture", "front_id.png"))).copy()
        a[:, :3] = a[:, 640:643]  # 把建築色塗到左緣 → 裁切
        a[300:400, 0:3] = man["parts"][0]["color"]
        Image.fromarray(a).save(os.path.join(tmp, "front_id.png"))
        r, _ = VA.reliability(tmp, man, e)
        check("H4", "建築碰到畫面邊緣 → UNKNOWN（CLIPPED）", (r["status"], "CLIPPED" in r["suggestion"]), ("UNKNOWN", True))
        Image.new("RGB", (640, 360)).save(os.path.join(tmp, "front.png"))
        r, _ = VA.reliability(tmp, man, e)
        check("H4", "解析度不符 → UNKNOWN", r["status"], "UNKNOWN")
        shutil.rmtree(tmp, ignore_errors=True)
        # C：審查意見定位（點到屋頂 → 幾何 PASS → REVIEW，不是 FAIL；點到背景 → 無法定位）
        roof_px = None
        ida = VA.img(os.path.join(out, "capture"), "front_id.png")
        rc_ = [p["color"] for p in man["parts"] if p["name"] == "roof"][0]
        ys, xs = np.nonzero(np.abs(ida - np.array(rc_)).max(axis=2) <= 12)
        roof_px = [int(xs.mean()), int(ys.mean())]
        rv = {"items": [{"image": "front.png", "px": roof_px, "concern": "offset", "observation": "屋頂看起來偏一邊"},
                        {"image": "front.png", "px": [5, 5], "concern": "other", "observation": "背景"}]}
        geo = json.load(open(os.path.join(out, "geometry.json"), encoding="utf-8"))["results"]
        mr = vqa.merge_review(rv, os.path.join(out, "capture"), man, geo)
        check("C", "審查點到屋頂 → ID 遮罩定位到 roof", mr[0]["object_ids"], ["roof"])
        check("C", "幾何 PASS 的視覺疑點 → REVIEW（不改模型）", mr[0]["status"], "REVIEW")
        check("C", "點到背景 → 無法定位 → REVIEW", (mr[1]["status"], mr[1]["object_ids"]), ("REVIEW", []))

    # G：最終判定優先級（純邏輯，不需要渲染）
    R = lambda rid, st, sec, **ev: {"rule_id": rid, "status": st, "section": sec, "evidence": ev}  # noqa: E731
    f = vqa.final_verdicts([R("roof_centered", "FAIL", "geometry"), R("VIS_SYMMETRY", "REVIEW", "visual", geometry=["roof_centered:FAIL"])])
    check("G", "幾何 FAIL＋視覺 REVIEW → 最終 FAIL", (f["per_rule"][0]["final"], f["overall"]), ("FAIL", "FAIL"))
    f = vqa.final_verdicts([R("roof_centered", "FAIL", "geometry"), R("VIS_OFFSET:roof_centered", "PASS", "visual")])
    check("G", "幾何 FAIL＋視覺 PASS → 最終 FAIL（不降級）", f["per_rule"][0]["final"], "FAIL")
    f = vqa.final_verdicts([R("x", "UNKNOWN", "geometry"), R("VIS_GAP:x", "PASS", "visual")])
    check("G", "幾何 UNKNOWN＋視覺 PASS → UNKNOWN（不升為 PASS）", f["per_rule"][0]["final"], "UNKNOWN")
    f = vqa.final_verdicts([R("x", "PASS", "geometry"), R("REVIEW:0", "REVIEW", "review", geometry_pass=["x"])])
    check("G", "幾何 PASS＋審查 REVIEW → REVIEW（往上提）", (f["per_rule"][0]["final"], f["overall"]), ("REVIEW", "REVIEW"))
    f = vqa.final_verdicts([R("x", "PASS", "geometry"), R("VIS_GAP:x", "FAIL", "visual")])
    check("G", "沒有幾何 FAIL 時視覺 FAIL 只算 REVIEW", f["per_rule"][0]["final"], "REVIEW")
    f = vqa.final_verdicts([R("x", "WARN", "geometry"), R("VIS_GAP:x", "PASS", "visual")])
    check("G", "幾何 WARN＋視覺 PASS → WARN", f["per_rule"][0]["final"], "WARN")

    if want("roof_offset"):  # 2 屋頂偏移
        rep, out, rc = run("roof_offset")
        fin = {p["rule_id"]: p for p in rep["final"]["per_rule"]}
        check("G", "實跑：roof_symmetric 幾何 FAIL＋VIS_SYMMETRY REVIEW → 最終 FAIL（鎖定）",
              (fin["roof_symmetric"]["final"], fin["roof_symmetric"]["locked"], "VIS_SYMMETRY:REVIEW" in fin["roof_symmetric"]["evidence"]),
              ("FAIL", True, True))
        check("G", "實跑：整棟最終 FAIL、exit 1", (rep["final"]["overall"], rc), ("FAIL", 1))
        r = row(rep, "VIS_OFFSET:roof_centered")
        check("2-roof", "幾何 FAIL＋俯視確認 → FAIL", r and r["status"], "FAIL", r and r["suggestion"])
        near("2-roof", "俯視量到的偏移（m）", r and r["actual"]["visual_m"], 0.18, 0.012)
        check("2-roof", "方向：建築座標右 −（與幾何 offset_frame_rfu 同號）", r and r["actual"]["right_m"] < -0.15, True)
        cap = os.listdir(os.path.join(out, "capture"))
        check("2-roof", "屋頂特寫（top／front）＋標註圖", all(f in cap for f in ("f00_top.png", "f00_front.png", "f00_top_annot.png")), True)
        check("2-roof", "特寫標記圖與原圖分開", "f00_top.png" in cap and "f00_top_annot.png" in cap, True)

    if want("post_float"):  # 3 柱腳懸空 7 mm＋修正預覽前後比較
        rep, out, rc = run("post_float")
        r = row(rep, "VIS_GAP:pe_on_base")
        check("3-float", "幾何 FAIL＋側視可見縫 → FAIL", r and r["status"], "FAIL", r and r["suggestion"])
        near("3-float", "影像量測縫隙（m）", r and r["actual"]["visual_m"], 0.007, 0.0015)
        check("3-float", "兩視角一致", r and r["actual"]["multi_view_consistent"], True)
        check("3-float", "視覺 FAIL 定位到具體物件", r and r["object_ids"], ["post_E", "base"])
        f = row(rep, "FIX_VISUAL:pe_on_base")
        check("3-float", "修正預覽後縫隙消失（未寫入）", f and f["status"], "PASS", f and str(f["actual"]))
        b = VA.img(os.path.join(out, "capture"), "f00_front.png")
        a = VA.img(os.path.join(out, "capture"), "f00_front_fix_pe_on_base.png")
        check("H4", "修正前後影像確實不同（比較有效）", float((np.abs(a - b).max(axis=2) > 10).mean()) > 0.001, True)
        check("3-float", ".blend 未被修改（預覽不寫入）", vqa.sha(f"{FX}/post_float.blend") == rep["meta"]["version"]["inputs"][f"{FX}/post_float.blend"]["sha"], True)
        # review-failures：只拍正視＋特寫
        rep2, out2, _ = run("post_float_rf", fx="post_float", mode="review-failures")
        files = os.listdir(os.path.join(out2, "capture"))
        check("A2", "review-failures 只拍 front＋特寫", (("back.png" in files), ("f00_right.png" in files)), (False, True))
        # 審查意見點到柱腳 → 幾何確認 FAIL
        man = VA.load(os.path.join(out, "capture"))
        ida = VA.img(os.path.join(out, "capture"), "front_id.png")
        col = [p["color"] for p in man["parts"] if p["name"] == "post_E"][0]
        ys, xs = np.nonzero(np.abs(ida - np.array(col)).max(axis=2) <= 12)
        rv = {"items": [{"image": "front.png", "px": [int(xs.mean()), int(ys.max()) - 3], "concern": "floating", "observation": "右柱腳好像沒落地"}]}
        mr = vqa.merge_review(rv, os.path.join(out, "capture"), man, json.load(open(os.path.join(out, "geometry.json"), encoding="utf-8"))["results"])
        check("C", "審查疑點 → 定位 post_E → 幾何確認 FAIL", (mr[0]["object_ids"], mr[0]["status"]), (["post_E"], "FAIL"))
        # 構件 id ≠ 物件名（hashira_E → post_E）：特寫、縫隙量測、審查定位都要照樣成立
        rep3, out3, _ = run("post_float_cid")
        r3 = row(rep3, "VIS_GAP:pe_on_base")
        check("cid", "構件 id≠物件名：特寫縫隙仍量到 7 mm", r3 and round(r3["actual"]["visual_m"], 3), 0.007)
        tg = json.load(open(os.path.join(out3, "targets.json"), encoding="utf-8"))
        check("cid", "目標錨點用物件名、保留構件 id", (tg["targets"][0]["anchor_object"], tg["targets"][0]["component_ids"]), ("post_E", ["hashira_E", "kidan"]))
        G3 = {"targets": tg}
        mr3 = vqa.merge_review(rv, os.path.join(out3, "capture"), VA.load(os.path.join(out3, "capture")),
                               json.load(open(os.path.join(out3, "geometry.json"), encoding="utf-8"))["results"], G3)
        check("cid", "審查定位 post_E → 找到構件 hashira_E 的 FAIL", mr3[0]["status"], "FAIL")

    if want("asym_roof"):  # 4 非對稱屋頂（社殿 profile、未宣告）→ REVIEW，不是 FAIL
        rep, out, rc = run("asym_roof")
        r = row(rep, "VIS_SYMMETRY")
        check("4-asym", "沒有幾何約束的視覺不對稱 → REVIEW", r and r["status"], "REVIEW", r and r["suggestion"])
        check("4-asym", "不產生 FAIL", rep["totals"]["FAIL"], 0)
        check("4-asym", "exit 3（REVIEW 不算通過）", rc, 3)

    if want("tenon"):  # 5 合法榫接
        rep, out, rc = run("tenon")
        check("5-tenon", "OVERLAP_ALLOWED 兩處 PASS", [row(rep, k)["status"] for k in ("beam_tenon_W", "beam_tenon_E")], ["PASS", "PASS"])
        check("5-tenon", "無 FAIL", rep["totals"]["FAIL"], 0)

    if want("module"):  # 6 模組接縫
        rep, out, rc = run("module", profile="generic_modular")
        check("6-module", "SNAP PASS", row(rep, "seam")["status"], "PASS")
        check("6-module", "無 FAIL／REVIEW", (rep["totals"]["FAIL"], rep["totals"]["REVIEW"]), (0, 0))

    if want("rotated"):  # 7 旋轉建築：相機跟建築主軸，不跟世界軸
        rep, out, rc = run("rotated", "--yaw=37", fx="ok")
        fr = rep["meta"]["frame"]
        near("7-rot", "建築正面 yaw（度）", fr["target_yaw_deg"], 37.0, 0.01)
        check("7-rot", "正交剪影尺寸＝建築尺寸（非世界軸 AABB）", sorted(set(statuses(rep, "VIS_SCALE").values())), ["PASS"])
        near("7-rot", "正視寬（m）", row(rep, "VIS_SCALE:front")["actual"]["width_m"], 5.0, 0.03)

    if want("nonuniform"):  # 8 非均勻縮放
        rep, out, rc = run("nonuniform", "--scale=1.3,1,0.8", fx="ok")
        near("8-scale", "正視寬 5.0×1.3", row(rep, "VIS_SCALE:front")["actual"]["width_m"], 6.5, 0.03)
        near("8-scale", "側視寬 3.4×0.8", row(rep, "VIS_SCALE:right")["actual"]["width_m"], 2.72, 0.03)
        check("8-scale", "取景全部 PASS", sorted(set(statuses(rep, "VIS_SCALE").values())), ["PASS"])

    if want("occluded"):  # 9 被其他物件遮擋 → UNKNOWN，不能當沒問題
        rep, out, rc = run("occluded", "--occluder=9,7,0.3@0,3,3.2", fx="ok")
        r = row(rep, "VIS_RELIABLE:front")
        check("9-occl", "正面被遮 → UNKNOWN（OCCLUDED）", (r["status"], "OCCLUDED" in r["suggestion"]), ("UNKNOWN", True), str(r["actual"]))
        check("9-occl", "背面不受影響 → PASS", row(rep, "VIS_RELIABLE:back")["status"], "PASS")
        check("9-occl", "exit 3（UNKNOWN 不算通過）", rc, 3)

    if want("tripo"):  # 10 單一 Mesh 的 Tripo 建築（真資產，唯讀）
        glb = os.path.join(ROOT, "godot", "assets", "shrine", "手水舍.glb")
        h0 = vqa.sha(glb)
        out = os.path.join(SCRATCH, "run_tripo")
        shutil.rmtree(out, ignore_errors=True)
        p = subprocess.run([sys.executable, os.path.join(HERE, "vqa.py"), "--mode=full", "--name=tripo", f"--glb={glb}", "--scan",
                            "--scale=3.2", "--profile=japanese_shrine", f"--out={out}"], capture_output=True, text=True, encoding="utf-8")
        rep = json.load(open(os.path.join(out, "report.json"), encoding="utf-8"))
        print("    tripo:", rep["totals"])
        check("10-tripo", "Scene Graph 單網格 → STRUCT:opaque UNKNOWN", row(rep, "STRUCT:opaque") and row(rep, "STRUCT:opaque")["status"], "UNKNOWN")
        check("10-tripo", "屋簷比例量不到 → UNKNOWN（不猜）", row(rep, "STYLE:roof_overhang_ratio")["status"], "UNKNOWN")
        check("10-tripo", "六視圖可靠", sorted(set(statuses(rep, "VIS_RELIABLE").values())), ["PASS"])
        check("10-tripo", "原始 GLB 未被修改", vqa.sha(glb), h0)

    if want("concept"):  # 11 概念圖 vs 模型比例
        rep, out, _ = run("concept_base", fx="ok")
        cap = os.path.join(out, "capture")
        man = VA.load(cap)
        sil = VA.union(VA.id_masks(VA.img(cap, "front_id.png"), man["parts"]))
        rgba = np.zeros(sil.shape + (4,), np.uint8)
        rgba[sil] = (40, 40, 40, 255)
        refimg = os.path.join(SCRATCH, "ref_ok_front.png")
        Image.fromarray(rgba).save(refimg)
        ref = {"image": refimg, "view": "front", "projection": "ortho", "approved": True, "approved_by": "test fixture"}
        rj = os.path.join(SCRATCH, "ref.json")
        json.dump(ref, open(rj, "w", encoding="utf-8"))
        rep, out, _ = run("concept_same", f"--ref={rj}", fx="ok", mode="visual-only", geo=False)
        r = row(rep, "REF_COMPARE")
        check("11-ref", "同模型 vs 參考 → PASS", r["status"], "PASS", str(r["actual"]["iou"]))
        rep, out, _ = run("concept_wide", f"--ref={rj}", fx="wide_roof", mode="visual-only", geo=False)
        r = row(rep, "REF_COMPARE")
        check("11-ref", "屋頂加寬 → REVIEW（不重建）", r["status"], "REVIEW", r["suggestion"])
        check("11-ref", "差異定位在屋頂高度段（≥ 75%）", r["actual"]["worst_band"]["band"] >= 15, True, str(r["actual"]["worst_band"]))
        ref2 = dict(ref, projection="perspective")
        check("11-ref", "視角／投影不一致 → UNKNOWN（不給分數）", VA.compare_reference(ref2, sil, {"view": "front", "projection": "ortho"})["status"], "UNKNOWN")
        ref3 = dict(ref, approved=False)
        check("11-ref", "未確認的參考圖 → UNKNOWN（不當標準答案）", VA.compare_reference(ref3, sil, {"view": "front", "projection": "ortho"})["status"], "UNKNOWN")

    if want("asym_house"):  # 12 正常但不對稱的日式建築
        rep, out, rc = run("asym_house", profile="japanese_house")
        check("12-house", "無 FAIL／REVIEW", (rep["totals"]["FAIL"], rep["totals"]["REVIEW"]), (0, 0),
              str([(r["rule_id"], r["status"]) for r in rep["results"] if r["status"] not in ("PASS",)]))
        check("12-house", "不對稱不被當錯（町家 profile 不要求對稱）", row(rep, "VIS_SYMMETRY")["status"], "PASS")
        check("12-house", "下屋搭接宣告 → PASS", [row(rep, k)["status"] for k in ("lean_into_body", "lean_on_wall")], ["PASS", "PASS"])

    if want("modes"):
        rep, out, rc = run("geo_only", fx="post_float", mode="geometry-only")
        check("A2", "geometry-only 不拍照", os.path.exists(os.path.join(out, "capture")), False)
        rep, out, rc = run("rf_clean", fx="ok", mode="review-failures")
        check("A2", "review-failures 沒有異常 → 不拍", os.path.exists(os.path.join(out, "capture")), False)

    bad = [r for r in results if not r[2]]
    print(f"[VQA-TEST] {len(results) - len(bad)}/{len(results)} ok")
    if "keep" not in A and not bad:
        shutil.rmtree(SCRATCH, ignore_errors=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
