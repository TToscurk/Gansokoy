"""幻想鄉緣一 建築／場景統一驗證入口（P2）：Geometry + Scene Graph + Placement + Visual QA → 一份報告。

  python tools/visual_qa/vqa.py --mode=full --name=<id> --glb=<a.glb>[,<b.glb>] \
      [--blend=<x.blend> --map=<x.arch.json> | --scan] [--profile=japanese_shrine] [--out=<dir>]
      [--yaw=deg --scale=s|sx,sy,sz --origin=x,y,z] [--corners] [--ref=<ref.json>] [--placement=<fastlane result.json>]
      [--review=<review.json>] [--occluder=sx,sy,sz@x,y,z] [--scene=res://… --node=<NodePath>]
  python tools/visual_qa/vqa.py --mode=map --scene=res://maps/village_v2/village_v2.tscn --region=x0,z0,x1,z1 \
      [--landmarks=Landmarks/A/Hero,…] [--max-views=4] [--out=<dir>]

模式：geometry-only｜visual-only｜full｜review-failures｜map
  review-failures：先跑幾何，只為非 PASS 的結果拍局部特寫（＋一張正視圖當上下文）；沒有異常就不拍。
全程唯讀：Blender 不存檔、Godot 不存場景、GLB 執行期載入（不匯入專案）。輸出只寫進 --out。
狀態：PASS／WARN／FAIL／UNKNOWN／REVIEW；UNKNOWN 與 REVIEW 永遠不計入 PASS。
exit：有 FAIL → 1；沒有 FAIL 但有 UNKNOWN／REVIEW → 3；其他 0。
"""
import hashlib
import json
import math
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np  # noqa: E402
import vqa_analyze as VA  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GD = os.path.join(ROOT, "godot")
GODOT = os.environ.get("GODOT_BIN") or os.environ.get("GODOT") or "D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
BLENDER = os.environ.get("BLENDER") or "D:/Blender/blender-5.2.1-windows-x64/blender.exe"
PROFILES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "profiles.json")
SIX = ["front", "back", "left", "right", "top", "oblique"]
TOOLS = ["tools/visual_qa/vqa.py", "tools/visual_qa/vqa_analyze.py", "tools/visual_qa/profiles.json",
         "godot/tools/visual_qa/vqa_capture.gd", "tools/blender/arch_spatial.py", "tools/blender/arch_check.py",
         "godot/tools/arch_spatial_lib.gd"]


def args():
    out = {}
    for a in sys.argv[1:]:
        k, _, v = a.lstrip("-").partition("=")
        out[k] = v if v else True
    return out


def log(*a):
    print("[VQA]", *a, flush=True)


def sha(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()[:16]
    except OSError:
        return None


def git(*a):
    try:
        return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, encoding="utf-8").stdout.strip()
    except OSError:
        return ""


def res_abs(p):
    return os.path.join(GD, p[6:]) if p.startswith("res://") else p


def version_info(inputs):
    """重現用：git HEAD、輸入檔雜湊、工具檔雜湊與是否有未提交修改。"""
    tools = {t: {"sha": sha(os.path.join(ROOT, t)), "dirty": bool(git("status", "--short", "--", t))} for t in TOOLS}
    ins = {}
    for p in inputs:
        if p:
            ap = res_abs(p)
            rel = os.path.relpath(ap, ROOT).replace("\\", "/") if ap.startswith(ROOT) else None
            ins[p] = {"sha": sha(ap), "dirty": bool(git("status", "--short", "--", rel)) if rel else None}
    return {"git_head": git("rev-parse", "--short", "HEAD"), "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
            "time": time.strftime("%Y-%m-%d %H:%M:%S"), "inputs": ins, "tools": tools,
            "godot_bin": GODOT, "blender_bin": BLENDER}


def run(cmd, logfile, timeout=1800):
    t = time.time()
    with open(logfile, "w", encoding="utf-8", errors="replace") as f:
        p = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
    return p.returncode, time.time() - t


def jload(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def jsave(p, o):
    with open(p, "w", encoding="utf-8") as f:
        json.dump(o, f, ensure_ascii=False, indent=1)


def vec(s, n=3, default=None):
    if s in (None, True, ""):
        return default
    v = [float(x) for x in str(s).split(",")]
    return v * n if len(v) == 1 else v


# ─────────────────────────── 1–3 幾何＋Scene Graph（Blender，沿用 arch_check） ───────────────────────────

def run_geometry(A, out):
    geo, graph, tg, fixp = (os.path.join(out, n) for n in ("geometry.json", "graph.json", "targets.json", "fix_preview.json"))
    logf = os.path.join(out, "blender.log")
    if A.get("blend") and A.get("map"):
        cmd = [BLENDER, "-b", A["blend"], "--python", os.path.join(ROOT, "tools/blender/arch_check.py"), "--",
               f"--map={A['map']}", f"--out={geo}", f"--graph={graph}", f"--targets={tg}", f"--fix-preview={fixp}"]
    elif A.get("scan") and A.get("glb"):
        first = A["glb"].split(",")[0]
        cmd = [BLENDER, "-b", "--factory-startup", "--python", os.path.join(ROOT, "tools/blender/arch_check.py"), "--",
               f"--glb={res_abs(first)}", "--scan", "--split", f"--out={geo}", f"--graph={graph}", f"--targets={tg}"]
        if A.get("scale") and "," not in str(A["scale"]):
            cmd.append(f"--scale={A['scale']}")
    else:
        return None
    rc, secs = run(cmd, logf)
    if not os.path.exists(geo):
        return {"error": f"Blender 幾何驗證沒有產出（exit {rc}），見 {logf}", "secs": secs}
    bs = float(A["scale"]) if A.get("scan") and A.get("scale") and "," not in str(A["scale"]) else 1.0
    return {"blender_scale": bs, "report": jload(geo), "graph": jload(graph) if os.path.exists(graph) else None,
            "targets": jload(tg) if os.path.exists(tg) else {"targets": []},
            "fix_preview": jload(fixp) if os.path.exists(fixp) else None, "secs": secs, "exit": rc}


# ─────────────────────────── 4 放置（快速通道 result.json） ───────────────────────────

def placement_rows(path):
    r = jload(path)
    rows = []
    for k, v in (r.get("checks") or {}).items():
        # 快速通道寫的是 "result"（PASS／REVIEW／FAIL）；讀不到狀態＝UNKNOWN，不是 FAIL（noka_b：5 項 PASS 被讀成 FAIL）
        st = (v.get("result") or v.get("status")) if isinstance(v, dict) else None
        if st is None and isinstance(v, dict) and ("pass" in v or "ok" in v):
            st = "PASS" if v.get("pass", v.get("ok")) else "FAIL"
        if st not in VA.STATUSES:
            st = "UNKNOWN"
        rows.append(VA.vrow(f"FASTLANE:{k}", "PLACEMENT", st, actual=v.get("detail") if isinstance(v, dict) else v,
                            method="godot/tools/fastlane/place_building.gd", section="placement"))
    for x in ((r.get("arch") or {}).get("results") or []):
        rows.append(dict(x, section="placement"))
    return rows


# ─────────────────────────── 5 拍攝（Godot） ───────────────────────────

def build_job(A, cap, mode, targets, fixp):
    job = {"out_dir": cap.replace("\\", "/"), "resolution": [int(x) for x in str(A.get("res", "1280x720")).split("x")],
           "settle_frames": int(A.get("settle", 10)), "repeat_check": mode != "review-failures", "taa": "taa" in A}
    if A.get("scene"):
        job.update(stage="scene", scene=A["scene"], node=A["node"])
    else:
        job["stage"] = "isolated"
        job["assets"] = [{"path": os.path.abspath(res_abs(p)).replace("\\", "/")} for p in A["glb"].split(",")]
        sc = vec(A.get("scale"), 3, [1, 1, 1])
        job["transform"] = {"yaw": float(A.get("yaw", 0)), "scale": sc, "origin": vec(A.get("origin"), 3, [0, 0, 0])}
        if A.get("occluder"):
            s, _, p = str(A["occluder"]).partition("@")
            job["occluders"] = [{"size": vec(s), "pos": vec(p)}]
    if A.get("front"):
        job["front_local"] = vec(A["front"])
    focus = []
    for i, t in enumerate((targets or {}).get("targets", [])):
        if t.get("anchor_object"):
            focus.append(dict(t, id=f"f{i:02d}"))
    if mode == "review-failures":
        job["views"] = ["front"]
    elif mode in ("full", "visual-only"):
        job["views"] = SIX
        job["corners"] = bool(A.get("corners"))
    job["focus"] = focus if mode in ("full", "review-failures") else []
    # 修正預覽：只有幾何預覽判 OK 的才拍「修正後」（BREAKS 的不拍，停在人）
    variants = []
    for p in (fixp or {}).get("previews", []):
        if p.get("verdict") != "OK":
            continue
        ff = [f for f in focus if f["rule_id"] == p["rule_id"]]
        if ff:
            variants.append({"name": "fix_" + p["rule_id"], "rule_id": p["rule_id"],
                             "moves": [{"node": n, "translate_blender": p["fix"]["translate"]} for n in p["moved"]],
                             "focus": ff})
    job["variants"] = variants if mode in ("full", "review-failures") else []
    return job


def run_capture(job, cap):
    os.makedirs(cap, exist_ok=True)
    jp = os.path.join(cap, "job.json")
    jsave(jp, job)
    w, h = job["resolution"]
    rc, secs = run([GODOT, "--path", GD, "--resolution", f"{w}x{h}", "--script", "res://tools/visual_qa/vqa_capture.gd",
                    "--", f"--job={jp}"], os.path.join(cap, "godot.log"))
    if not os.path.exists(os.path.join(cap, "manifest.json")):
        return None, secs, rc
    return VA.load(cap), secs, rc


# ─────────────────────────── 6 視覺分析＋幾何交叉驗證 ───────────────────────────

def profile_for(A, bid):
    P = jload(PROFILES)
    canon = None
    hay = " ".join(str(x) for x in (bid, A.get("glb", ""), A.get("scene", ""), A.get("node", ""))).lower()
    for k, c in P["project_canon"].items():
        if k.startswith("_"):
            continue
        if any(m.lower() in hay for m in c["match"]):
            canon = dict(c, id=k)
            break
    pid = A.get("profile") or (canon or {}).get("profile") or "generic_modular"
    return pid, P["profiles"].get(pid), canon


def obj_names(G, ids):
    """結果列的 object_ids（map 模式是構件 id）→ Blender／GLB 物件名。"""
    cm = ((G or {}).get("targets") or {}).get("cid_map") or {}
    return [cm.get(i, i) for i in ids or []]


def dependents(G, obj):
    """Scene Graph：被 obj 支撐／附著的構件（遞迴）。移動 obj 之前必須一起考慮的範圍。"""
    g = (G or {}).get("graph") or {}
    cm = ((G or {}).get("targets") or {}).get("cid_map") or {}
    inv = {v: k for k, v in cm.items()}
    start = inv.get(obj, obj)
    out, todo = [], [start]
    while todo:
        c = todo.pop()
        for e in g.get("edges", []):
            nxt = e["dst"] if e["rel"] == "SUPPORTS" and e["src"] == c else (
                e["src"] if e["rel"] == "ATTACHED_TO" and e["dst"] == c else None)
            if nxt and nxt not in out and nxt != start:
                out.append(nxt)
                todo.append(nxt)
    return out


def geo_rows_for(geo_rows, names, G=None):
    s = set(names)
    return [r for r in geo_rows if s & (set(r.get("object_ids") or []) | set(obj_names(G, r.get("object_ids"))))]


def analyze(A, cap, man, G, prof_id, prof, canon, spec):
    rows, views, art = [], {}, {"view_files": [], "focus_files": [], "fix_files": []}
    geo_rows = (G or {}).get("report", {}).get("results", []) if G and "report" in G else []
    for e in man["images"]:
        if e.get("kind") != "view" or e["file"].endswith("_repeat.png"):
            continue
        r, mk = VA.reliability(cap, man, e)
        rows.append(r)
        views[e["view"]] = (e, mk, r["status"])
        art["view_files"].append((e["file"], f"{e['view']} {e.get('projection', '')}"))
        if mk and r["status"] != "UNKNOWN":
            sc = VA.silhouette_scale(man, e, mk[1])
            if sc:
                rows.append(sc)
    # 同一場景重拍是否一致
    rep = [e for e in man["images"] if e.get("file") == "front_repeat.png"]
    if rep and "front" in views:
        a, b = VA.img(cap, "front.png"), VA.img(cap, "front_repeat.png")
        d = np.abs(a - b)
        changed = float((d.max(axis=2) > VA.DIFF_TOL).mean())
        rows.append(VA.vrow("VIS_REPEAT:front", "CAPTURE", "PASS" if changed < 0.0005 else "WARN",
                            expected={"changed_pixels": "<0.05%（TAA 關閉時實測 0）"}, actual={"mean_abs": round(float(d.mean()), 4),
                            "changed_pixels": round(changed, 6)}, method="同相機重拍逐像素差",
                            suggestion="" if changed < 0.0005 else "同條件重拍有差異（--taa、動態植被、粒子或風力 shader），前後比較需扣除此雜訊",
                            images=["front.png", "front_repeat.png"]))
    # Blender 物件 ↔ GLB 節點對應（特寫錨點靠這個）：尺寸要一致；位置不同只代表 GLB 另有原點
    bb = ((G or {}).get("targets") or {}).get("bounds_blender") or {}
    pl = man.get("part_local_bounds") or {}
    if bb and pl:
        k = 1.0 / float((G or {}).get("blender_scale", 1.0))  # 兩邊都換回 GLB 局部（未縮放）座標再比
        bb = {nm: {"min": [x * k for x in b["min"]], "max": [x * k for x in b["max"]]} for nm, b in bb.items()}
        bad, same_pos, n = [], 0, 0
        for nm, b in bb.items():
            g = pl.get(nm) or pl.get(nm.replace(".", "_"))
            if not g:
                continue
            n += 1
            bs = [b["max"][0] - b["min"][0], b["max"][2] - b["min"][2], b["max"][1] - b["min"][1]]  # (x, z, y) → Godot (x, y, z)
            gs = [g["max"][i] - g["min"][i] for i in range(3)]
            if any(abs(bs[i] - gs[i]) > max(0.005, 0.01 * bs[i]) for i in range(3)):
                bad.append({"object": nm, "blender_size_godot_axes": [round(x, 4) for x in bs], "godot_size": [round(x, 4) for x in gs]})
            bc = [(b["max"][0] + b["min"][0]) / 2, (b["max"][2] + b["min"][2]) / 2, -(b["max"][1] + b["min"][1]) / 2]
            gc = [(g["max"][i] + g["min"][i]) / 2 for i in range(3)]
            same_pos += all(abs(bc[i] - gc[i]) <= 0.01 for i in range(3))
        if n:
            rows.append(VA.vrow("VIS_MAPPING", "MAPPING", "PASS" if not bad else "FAIL", expected="Blender 物件尺寸＝GLB 節點尺寸",
                                actual={"matched": n, "size_mismatch": bad, "same_position": same_pos},
                                method="Blender 世界 AABB (x,z,y)÷Blender 端縮放 vs Godot 目標局部 AABB（都是 GLB 未縮放座標）",
                                suggestion=("" if not bad else "GLB 與 .blend 不是同一版本：特寫錨點與幾何結論不能套到這個 GLB")
                                + ("" if same_pos == n else f"；{n - same_pos} 個物件位置不同（GLB 另有原點，錨點用相對座標仍正確）")))
    ok_view = lambda v: v in views and views[v][1] is not None and views[v][2] != "UNKNOWN"  # noqa: E731
    fr = man["frame"]
    size = fr["size_rfu"]
    # 地面融合（審查舞台：最低點 vs 地面 y=0）
    if man.get("stage") == "isolated":
        lo_y = fr["origin"][1] + fr["box_rfu_min"][1]   # 世界 y（建築座標是公尺、原點＝目標原點）
        gy = 0.0
        emb = float((spec or {}).get("ground_embed_max", 0.0))  # 連接表宣告的設計埋入深度
        st = "PASS" if -emb - 0.02 <= lo_y - gy <= 0.02 else ("FAIL" if lo_y - gy > 0.02 else "WARN")
        sug = {"FAIL": "整棟浮在地面上方",
               "WARN": f"最低點在地面下 {gy - lo_y:.3f} m（埋入）：若是基座設計，在連接表宣告 ground_embed_max；否則檢查原點"}.get(st, "")
        if st == "PASS" and lo_y < gy - 0.02:
            sug = f"埋入 {gy - lo_y:.3f} m ≤ 宣告 ground_embed_max {emb} m（INTENTIONAL）"
        rows.append(VA.vrow("VIS_GROUND", "GROUND", st, expected={"lowest_y": gy, "embed_max": emb}, actual={"lowest_y": lo_y},
                            deviation=round(lo_y - gy, 4), tol=0.02, method="Godot 實際網格最低點（建築座標）vs 審查地面",
                            suggestion=sug, error_class="INTENTIONAL" if "INTENTIONAL" in sug else None))
    # 對稱（C1／C2：正視 IoU 與左右立面互相鏡射）
    intentional = set((spec or {}).get("intentional_asymmetry") or [])
    sym_geo = [r for r in geo_rows if r["type"] == "SYMMETRIC"]
    if ok_view("front"):
        e, mk, _ = views["front"]
        sm = VA.symmetry(man, e, mk[1])
        if sm:
            need = (prof or {}).get("symmetry", {})
            bil = need.get("expected") == "bilateral"
            thr = need.get("silhouette_iou_min", 0.9)
            side = None
            if ok_view("left") and ok_view("right"):
                L, R = views["left"][1][1], views["right"][1][1]
                side = float((L & R[:, ::-1]).sum() / max(1, (L | R[:, ::-1]).sum()))
            act = dict(sm, left_right_elevation_iou=None if side is None else round(side, 4))
            if sym_geo:
                gfail = any(r["status"] == "FAIL" for r in sym_geo)
                vfail = sm["iou"] < thr
                if gfail == vfail:
                    st, sug, ec = ("FAIL" if gfail else "PASS"), ("幾何與正視剪影一致：" + ("不對稱" if gfail else "對稱")), \
                        ("GEOMETRY_ERROR" if gfail else None)
                else:
                    st, ec = "REVIEW", "VISUAL_SUSPECT"
                    sug = (f"幾何 SYMMETRIC {'FAIL' if gfail else 'PASS'} 但正視剪影 IoU {sm['iou']:.3f}"
                           f"{'≥' if not vfail else '<'}{thr}：檢查是否為其他構件（裝飾／附屬）造成，或透視／相機問題；不自動修改")
                rows.append(VA.vrow("VIS_SYMMETRY", "SYMMETRY", st, [r["object_ids"][0] for r in sym_geo],
                                    {"iou": f">={thr}"}, act, method="正交正視剪影對建築原點中軸鏡射 IoU＋幾何 SYMMETRIC",
                                    suggestion=sug, error_class=ec, images=[e["file"], e["id"]],
                                    evidence={"geometry": [r["rule_id"] + ":" + r["status"] for r in sym_geo]}))
            elif bil and sm["iou"] < thr:
                if intentional or (canon and canon.get("allow_weathered") and sm["iou"] >= thr - 0.05):
                    rows.append(VA.vrow("VIS_SYMMETRY", "SYMMETRY", "PASS", sorted(intentional), {"iou": f">={thr}"}, act,
                                        method="正交正視剪影 IoU", suggestion="不對稱已宣告為刻意設計（INTENTIONAL）",
                                        error_class="INTENTIONAL", images=[e["file"], e["id"]]))
                else:
                    side_txt = "右" if sm["extent_right_m"] > sm["extent_left_m"] else "左"
                    rows.append(VA.vrow("VIS_SYMMETRY", "SYMMETRY", "REVIEW", [], {"iou": f">={thr}"}, act,
                                        method="正交正視剪影對建築原點中軸鏡射 IoU（沒有幾何 SYMMETRIC 約束）",
                                        suggestion=(f"{prof_id} 預期左右對稱，但影像{side_txt}側多出 "
                                                    f"{abs(sm['extent_right_m'] - sm['extent_left_m']):.2f} m；沒有幾何約束能確認，"
                                                    "請人判斷是否刻意（是的話在連接表加 intentional_asymmetry）"),
                                        error_class="VISUAL_SUSPECT", images=[e["file"], e["id"]]))
            else:
                rows.append(VA.vrow("VIS_SYMMETRY", "SYMMETRY", "PASS", [], {"expected": need.get("expected"), "iou_min": thr},
                                    act, method="正交正視剪影 IoU", images=[e["file"], e["id"]],
                                    suggestion="" if bil else "此風格不要求對稱（只記錄）"))
    # 比例（D：只 WARN）
    prop = (prof or {}).get("proportions", {})
    if prop:
        W, H, D = size[0], size[1], size[2]
        for key, val in (("height_to_width", H / W if W else None), ("depth_to_width", D / W if W else None)):
            rg = prop.get(key)
            if rg and val is not None:
                ok = rg[0] <= val <= rg[1]
                rows.append(VA.vrow(f"STYLE:{key}", "STYLE", "PASS" if ok else "WARN", expected=rg, actual=round(val, 3),
                                    method=f"Godot 實測緊貼盒 寬{W:.2f}×高{H:.2f}×深{D:.2f} m；profile={prof_id}",
                                    suggestion="" if ok else "超出風格常見比例：人工確認（不是幾何錯誤）",
                                    error_class=None if ok else "STYLE_DEVIATION", section="style"))
        rg = prop.get("roof_overhang_ratio")
        nodes = ((G or {}).get("graph") or {}).get("nodes") or {}
        roofs = [n["object"] for n in nodes.values() if n.get("type") == "roof" and n.get("role") != "lean_to"
                 and n["id"] not in intentional]
        structs = [n["object"] for n in nodes.values() if n.get("type") in ("post", "wall") and n["id"] not in intentional]
        typed = any(n.get("type") for n in nodes.values())
        if rg and typed and not roofs:
            rg = None  # 有分類但沒有屋頂（模組牆等）：此項不適用，不算 UNKNOWN
        if rg and ok_view("front"):
            masks = views["front"][1][0]
            rb = [VA.bbox(masks[r]) for r in roofs if r in masks and masks[r].any()]
            sb = [VA.bbox(masks[s]) for s in structs if s in masks and masks[s].any()]
            if rb and sb:
                rw = max(b[2] for b in rb) - min(b[0] for b in rb) + 1
                sw = max(b[2] for b in sb) - min(b[0] for b in sb) + 1
                val = rw / sw
                ok = rg[0] <= val <= rg[1]
                rows.append(VA.vrow("STYLE:roof_overhang_ratio", "STYLE", "PASS" if ok else "WARN", roofs + structs, rg,
                                    round(val, 3), method="正視 ID 遮罩：屋頂寬／柱牆外緣寬", section="style",
                                    suggestion="" if ok else "屋簷出挑比例超出風格常見範圍（人工確認）",
                                    error_class=None if ok else "STYLE_DEVIATION", images=[views["front"][0]["id"]]))
            else:
                rows.append(VA.vrow("STYLE:roof_overhang_ratio", "STYLE", "UNKNOWN", expected=rg, section="style",
                                    method="需要連接表把構件標成 roof 與 post/wall",
                                    suggestion="沒有可辨識的屋頂與柱牆構件（單網格或未分類），無法量出挑"))
    # 預期構件關係（D：查 Scene Graph）
    g = (G or {}).get("graph")
    for sup, dep, rel in (prof or {}).get("expected_relations", []):
        if not g:
            break
        deps = [n for n in g["nodes"].values() if n.get("type") == dep]
        if not deps:
            continue
        for n in deps:
            sups = sup.split("|")
            ty = lambda k: (g["nodes"].get(k) or {}).get("type")  # noqa: E731
            es = [x for x in g["edges"] if x["rel"] in rel.split("|") and (
                  (x["dst"] == n["id"] and ty(x["src"]) in sups) or  # SUPPORTS：src 撐 dst
                  (x["rel"] == "CONNECTED" and x["src"] == n["id"] and ty(x["dst"]) in sups))]  # CONNECTED 無方向
            if any(x["status"] == "PASS" for x in es):
                st, sug = "PASS", ""
            elif es:
                st, sug = "WARN", f"{sup} {rel} {n['id']} 的邊存在但未通過：{[x['rule_id'] for x in es]}（幾何 FAIL 見 Geometry 段）"
            else:
                st, sug = "WARN", f"Scene Graph 找不到 {sup} {rel} {n['id']}：構件可能沒有受力路徑（或連接表沒宣告）"
            rows.append(VA.vrow(f"STRUCT:{sup}>{n['id']}", "STRUCTURE", st, [n["object"]], f"{sup} {rel} {dep}",
                                [x["src"] + ":" + x["status"] for x in es], method="Scene Graph 查詢",
                                suggestion=sug, error_class=None if st == "PASS" else "STRUCTURAL_ERROR", section="style"))
    if g and any(n.get("type") == "opaque" or n.get("opaque") for n in g["nodes"].values()):
        rows.append(VA.vrow("STRUCT:opaque", "STRUCTURE", "UNKNOWN", list(g["nodes"]), method="Scene Graph",
                            suggestion="單一網格（Tripo）：內部構件無法辨識，柱梁屋頂關係無法驗證；不為此重建資產",
                            evidence={"limits": g.get("limits")}, section="style"))
    # COAXIAL（屋頂偏移等）：俯視 ID 遮罩量兩構件重心差，與幾何偏差比對
    for r in geo_rows:
        if r["type"] != "COAXIAL" or len(r.get("object_ids") or []) < 2 or not ok_view("top"):
            continue
        e, mk, _ = views["top"]
        a, b = obj_names(G, r["object_ids"][:2])
        solo = e.get("part_solo") or {}
        if a not in solo or b not in solo:
            continue
        pm = {k: VA.id_masks(VA.img(cap, solo[k]), man["parts"])[k] for k in (a, b)}  # 單獨渲染：不受其他構件遮擋
        ca, cb = VA.part_centroid_rfu(man, e, pm[a]), VA.part_centroid_rfu(man, e, pm[b])
        if ca is None or cb is None:
            rows.append(VA.vrow(f"VIS_OFFSET:{r['rule_id']}", "OFFSET", "UNKNOWN", [a, b], method="top ortho part-solo id mask",
                                suggestion="俯視單獨遮罩裡沒有其中一個構件（不在畫面內）"))
            continue
        dv = cb - ca
        vis_off = math.hypot(dv[0], dv[2])
        act = r.get("actual") if isinstance(r.get("actual"), dict) else {}
        geo_off = act.get("offset")  # 原始偏移（deviation 是扣掉容差後的超出量，不能拿來比）
        gv = act.get("offset_frame_rfu")
        tolv = 2 * e["m_per_px"] + 0.1 * (geo_off or 0)
        agree = geo_off is not None and abs(vis_off - geo_off) <= tolv
        if agree and gv and geo_off > tolv:  # 方向也要一致（建築座標 right／front），不只大小
            gd = np.array([gv[0], gv[2]])
            agree = float(np.dot(gd, [dv[0], dv[2]])) > 0.8 * np.linalg.norm(gd) * vis_off
        if r["status"] == "FAIL":
            st = "FAIL" if agree else "REVIEW"
            sug = (f"幾何 FAIL {geo_off*1000:.0f} mm；俯視圖量到 {vis_off*1000:.0f} mm（右 {dv[0]*1000:+.0f}／前 {dv[2]*1000:+.0f} mm）"
                   + ("，視覺確認" if agree else "，視覺量測與幾何不一致：檢查可見構件是否被遮擋或部分隱藏"))
        else:
            st = "PASS" if vis_off <= max(tolv, 0.02) else "REVIEW"
            sug = "" if st == "PASS" else f"幾何 PASS 但俯視圖重心差 {vis_off*1000:.0f} mm（可能是構件形狀不對稱，不是位移）"
        rows.append(VA.vrow(f"VIS_OFFSET:{r['rule_id']}", "OFFSET", st, [a, b], {"geometry_m": geo_off},
                            {"visual_m": round(vis_off, 4), "right_m": round(float(dv[0]), 4), "front_m": round(float(dv[2]), 4)},
                            round(vis_off - (geo_off or 0), 4), tolv, "top ortho 逐構件單獨 id 遮罩重心（投影面積重心，非體積重心）",
                            sug, error_class="GEOMETRY_ERROR" if st == "FAIL" else None, images=[e["file"], e["id"]],
                            evidence={"geometry_rule": r["rule_id"], "geometry_status": r["status"]}))
    # 局部特寫（B3）：SUPPORT → 柱腳縫；其他 → 標註
    focus = {}
    for e in man["images"]:
        if e.get("kind") == "focus":
            focus.setdefault((e.get("focus"), e.get("variant") or ""), []).append(e)
    tmap = {f"f{i:02d}": t for i, t in enumerate((G or {}).get("targets", {}).get("targets", []))}
    for (fid, var), es in sorted(focus.items()):
        t = tmap.get(fid, {})
        for e in es:
            if e.get("status") == "UNKNOWN":
                rows.append(VA.vrow(f"VIS_FOCUS:{e.get('rule_id')}", "FOCUS", "UNKNOWN", method="focus capture",
                                    suggestion=e.get("reason", "")))
                continue
        es = [e for e in es if e.get("status") != "UNKNOWN"]
        gaps = []
        for e in es:
            ida = VA.img(cap, e["id"])
            mk = VA.id_masks(ida, man["parts"], man.get("ground_color"))
            labels = [f"{t.get('rule_id')} [{t.get('status')}] {e['view']}{' ' + var if var else ''}",
                      f"幾何：{(t.get('suggestion') or '')[:60]}", f"解析度 {e['m_per_px']*1000:.2f} mm/px"]
            boxes = []
            objs = e.get("objects") or []
            for k, col in zip(objs[:2], ((255, 80, 80), (80, 200, 255))):
                if k in mk and mk[k].any():
                    boxes.append((VA.bbox(mk[k]), col))
            if t.get("type") == "SUPPORT" and len(objs) >= 2 and objs[0] in mk and objs[1] in mk:
                gp = VA.gap_between(man, e, mk[objs[0]], mk[objs[1]])
                if gp:
                    gaps.append((e, gp))
                    labels.append(f"影像量測縫隙 {gp['median_m']*1000:.1f} mm（{gp['median_px']:.0f} px）")
            name = VA.annotate(cap, e, labels, boxes)
            if var:
                art["fix_files"].append((f"{fid}_{e['view']}_annot.png", name, f"{fid} {e['view']}"))
            else:
                art["focus_files"].append((name, f"{fid} {e['view']}"))
        if t.get("type") == "SUPPORT":
            gm = (t.get("actual") or {}).get("median_gap") if isinstance(t.get("actual"), dict) else None
            if not gaps:
                rows.append(VA.vrow(f"VIS_GAP:{t.get('rule_id')}{':' + var if var else ''}", "GAP", "UNKNOWN", t.get("object_ids"),
                                    method="side ortho id mask", suggestion="特寫中兩構件沒有上下重疊的欄，量不到縫"))
                continue
            vals = [gp["median_m"] for _, gp in gaps]
            resm = max(gp["resolution_m"] for _, gp in gaps)
            vis = float(np.median(vals))
            consistent = max(vals) - min(vals) <= 2 * resm
            below = vis < 1.5 * resm
            if var:  # 修正後：縫應該消失
                st = "PASS" if below else "FAIL"
                rows.append(VA.vrow(f"FIX_VISUAL:{t.get('rule_id')}", "FIX_PREVIEW", st, t.get("object_ids"),
                                    {"gap_after_m": f"<{1.5*resm:.4f}"}, {"gap_after_m": round(vis, 4), "views": len(vals)},
                                    method="修正預覽（記憶體內平移）後同相機重拍＋縫隙量測",
                                    suggestion="修正後縫隙消失（未寫入任何檔案）" if st == "PASS" else "修正後仍看得到縫",
                                    images=[e["file"] for e, _ in gaps], section="fix"))
                continue
            deps = dependents(G, (t.get("object_ids") or [None])[0])
            if t.get("status") == "FAIL" and not below:
                st, sug = "FAIL", (f"幾何 FAIL（中位間隙 {gm*1000:.1f} mm）；側視圖確認可見縫隙 {vis*1000:.1f} mm"
                                   f"（{len(vals)} 個視角{'一致' if consistent else '不一致'}）。"
                                   + (f"移動 {t['object_ids'][0]} 前：它支撐 {' → '.join(deps)}（Scene Graph），要一起移或改墊高支撐面"
                                      if deps else "Scene Graph 沒有依賴它的構件，可單獨修"))
            elif t.get("status") == "FAIL":
                st, sug = "UNKNOWN", f"幾何 FAIL {gm*1000:.1f} mm，但小於影像解析度 {resm*1000:.2f} mm/px×1.5，視覺無法確認（幾何結論不變）"
            else:
                st, sug = ("REVIEW" if not below else "PASS"), "幾何非 FAIL；視覺量測僅供參考"
            rows.append(VA.vrow(f"VIS_GAP:{t.get('rule_id')}", "GAP", st, t.get("object_ids"), {"geometry_m": gm},
                                {"visual_m": round(vis, 5), "per_view_m": [round(v, 5) for v in vals], "multi_view_consistent": consistent},
                                round(vis - (gm or 0), 5), 2 * resm, "side/front ortho id-mask column gap", sug,
                                error_class="GEOMETRY_ERROR" if st == "FAIL" else None,
                                images=[e["file"].replace(".png", "_annot.png") for e, _ in gaps],
                                camera=gaps[0][0]["camera"], evidence={"geometry_rule": t.get("rule_id"), "scene_graph_dependents": deps}))
    # 修正預覽 BREAKS：明確停下
    for p in ((G or {}).get("fix_preview") or {}).get("previews", []):
        if p.get("verdict") != "OK":
            rows.append(VA.vrow(f"FIX_VISUAL:{p['rule_id']}", "FIX_PREVIEW", "WARN",
                                p.get("moved"), actual={"verdict": p["verdict"], "new_failures": p.get("new_failures")},
                                method="arch_spatial.fix_preview", suggestion=p.get("note") or "建議的平移不能讓此規則通過（NOT_FIXED）：不拍修正後圖，需要人決定修法", section="fix"))
    # 參考圖（E）
    if A.get("ref"):
        ref = jload(A["ref"])
        if "front" in views and views["front"][1] is not None:
            e, mk, _ = views["front"]
            rows.append(VA.compare_reference(ref, mk[1], e))
        else:
            rows.append(VA.vrow("REF_COMPARE", "REFERENCE", "UNKNOWN", suggestion="沒有可靠的正視圖可比"))
    return rows, art



# ─────────────────────────── C 視覺審查（審查者意見 → 定位 → 幾何查證） ───────────────────────────

def review_request(out, cap, man, G, rows, prof_id, prof, art):
    """給 Visual Reviewer 的獨立資料：截圖＋量測事實＋風格清單。不含建模階段的自我描述。"""
    facts = [f"{r['rule_id']} {r['status']}: {r.get('suggestion') or ''}" for r in rows if r["status"] != "PASS"]
    geo = [f"{r['rule_id']} {r['status']} dev={r.get('deviation')}" for r in (G or {}).get("report", {}).get("results", [])] \
        if G and "report" in G else []
    req = {"images": [os.path.join(cap, f) for f, _ in art["view_files"] + art["focus_files"]],
           "profile": prof_id, "checklist": [
               "柱子與橫梁視覺上是否連接（看特寫，不看遠景）", "屋頂是否相對建築主軸偏移（看 top 正交）",
               "左右立面是否異常（left vs right）", "入口／樓梯是否接到入口", "建築是否與地面融合（柱腳、基壇）",
               "比例是否合理（以公尺量測為準，不以單張透視圖判斷）", "是否有不自然的懸浮或遮擋構件"],
           "geometry_facts": geo, "open_items": facts,
           "graph": ((G or {}).get("graph") or {}).get("limits"),
           "format": {"items": [{"image": "front.png", "px": [640, 300], "object": "(可省略，會用 ID 遮罩定位)",
                                 "concern": "offset|floating|gap|scale|penetration|style|other", "observation": "..."}]},
           "rules": "每一項只描述看到什麼與在哪裡；不要估精確公尺數；系統會用 ID 遮罩定位物件並查幾何。"}
    jsave(os.path.join(out, "review_request.json"), req)
    return req


def merge_review(rv, cap, man, geo_rows, G=None):
    rows = []
    by_file = {e["file"]: e for e in man["images"] if e.get("file")}
    for i, it in enumerate(rv.get("items", [])):
        obj = it.get("object")
        e = by_file.get(it.get("image"))
        how = "reviewer"
        if not obj and e and e.get("id") and it.get("px"):
            ida = VA.img(cap, e["id"])
            x, y = int(it["px"][0]), int(it["px"][1])
            win = ida[max(0, y - 6):y + 7, max(0, x - 6):x + 7].reshape(-1, 3)
            px = ida[min(max(y, 0), ida.shape[0] - 1), min(max(x, 0), ida.shape[1] - 1)]
            best = 0
            for p in man["parts"]:
                if np.abs(px - np.array(p["color"])).max() <= VA.ID_TOL:  # 點到的那個像素優先
                    obj, how, best = p["name"], "id_mask(pixel)", 10 ** 9
                    break
                cnt = int((np.abs(win - np.array(p["color"])).max(axis=1) <= VA.ID_TOL).sum())
                if cnt > best:  # 否則取 13×13 視窗內像素最多的構件
                    obj, how, best = p["name"], "id_mask(window majority)", cnt
        persp = bool(e and e.get("projection") == "perspective")
        base = dict(objs=[obj] if obj else [], images=[it.get("image")], section="review",
                    camera=e.get("camera") if e else None)
        if not obj:
            rows.append(VA.vrow(f"REVIEW:{i}", "VISUAL_REVIEW", "REVIEW", method="reviewer item, not located",
                                actual=it, suggestion="無法定位到具體物件：需要人看", error_class="VISUAL_SUSPECT", **{k: v for k, v in base.items() if k != "objs"}))
            continue
        gr = geo_rows_for(geo_rows, [obj], G)
        fails = [r for r in gr if r["status"] == "FAIL"]
        if fails:
            rows.append(VA.vrow(f"REVIEW:{i}", "VISUAL_REVIEW", "FAIL", actual=it, method=f"located by {how} → geometry",
                                suggestion=f"視覺疑點由幾何確認：{[r['rule_id'] + ' ' + (r.get('suggestion') or '') for r in fails]}",
                                error_class="GEOMETRY_ERROR", evidence={"geometry": [r["rule_id"] for r in fails]}, **base))
        elif gr:
            why = "透視視角，先用正交視圖確認" if persp else "幾何全部 PASS：可能是屋頂曲線、刻意不對稱或材質造成的錯覺"
            rows.append(VA.vrow(f"REVIEW:{i}", "VISUAL_REVIEW", "REVIEW", actual=it, method=f"located by {how} → geometry PASS",
                                suggestion=f"幾何與視覺不一致（{why}）；不修改模型，交給人確認",
                                error_class="VISUAL_SUSPECT", evidence={"geometry_pass": [r["rule_id"] for r in gr]}, **base))
        else:
            rows.append(VA.vrow(f"REVIEW:{i}", "VISUAL_REVIEW", "REVIEW", actual=it, method=f"located by {how}",
                                suggestion="此物件沒有任何幾何規則可查證：補連接表約束或人工確認", error_class="VISUAL_SUSPECT", **base))
    return rows


# ─────────────────────────── 7–8 報告 ───────────────────────────

SECTION_NAME = {"geometry": "Geometry", "placement": "Placement", "visual": "Visual", "style": "Style／Structure",
                "fix": "Fix preview", "review": "Visual review", "map": "Map"}


def summarize(rows):
    s = {}
    for r in rows:
        sec = r.get("section", "geometry")
        s.setdefault(sec, {k: 0 for k in VA.STATUSES})
        s[sec][r["status"]] = s[sec].get(r["status"], 0) + 1
    tot = {k: sum(v.get(k, 0) for v in s.values()) for k in VA.STATUSES}
    return s, tot


RANK = {"PASS": 0, "WARN": 1, "UNKNOWN": 2, "REVIEW": 3, "FAIL": 4}
EVIDENCE_SECTIONS = ("visual", "review", "style")  # 只能補證據、不能決定硬性結果的區段


def _links(r):
    """視覺／審查列連到哪些幾何規則 id。"""
    ev = r.get("evidence") or {}
    out = set()
    if ev.get("geometry_rule"):
        out.add(ev["geometry_rule"])
    for x in (ev.get("geometry") or []) + (ev.get("geometry_pass") or []):
        out.add(str(x).split(":")[0])
    rid = r["rule_id"]
    if ":" in rid and rid.split(":")[0] in ("VIS_GAP", "VIS_OFFSET"):
        out.add(rid.split(":", 1)[1])
    return out


def final_verdicts(rows):
    """最終判定（P2-G）：硬性幾何／放置結果是底線，視覺只能補證據或往上提到 REVIEW，不能往下降。
    - 幾何 FAIL → 最終 FAIL（不論視覺 PASS／REVIEW／UNKNOWN）
    - 幾何 UNKNOWN → 視覺 PASS 不能把它變成 PASS
    - 幾何 PASS／WARN ＋ 視覺 REVIEW → REVIEW；視覺單獨的 FAIL 也只算 REVIEW（沒有幾何證據不准 FAIL）"""
    hard = [r for r in rows if r.get("section", "geometry") in ("geometry", "placement", "map")]
    soft = [r for r in rows if r.get("section") in EVIDENCE_SECTIONS]
    per = []
    for g in hard:
        ev = [v for v in soft if g["rule_id"] in _links(v)]
        st = g["status"]
        if st != "FAIL":
            for v in ev:
                vs = "REVIEW" if v["status"] == "FAIL" else v["status"]
                if vs == "PASS" or RANK[vs] <= RANK[st]:
                    continue
                st = vs
        per.append({"rule_id": g["rule_id"], "geometry": g["status"], "priority": g.get("priority", "hard"),
                    "evidence": [f"{v['rule_id']}:{v['status']}" for v in ev], "final": st,
                    "locked": g["status"] == "FAIL"})
    linked = {v["rule_id"] for v in soft for g in hard if g["rule_id"] in _links(v)}
    loose = [{"rule_id": v["rule_id"], "final": v["status"]} for v in rows
             if v.get("section") not in ("geometry", "placement", "map") and v["rule_id"] not in linked]
    allst = [x["final"] for x in per + loose]
    overall = max(allst, key=lambda s: RANK[s]) if allst else "UNKNOWN"
    return {"overall": overall, "per_rule": per, "unlinked": loose,
            "rule": "幾何／放置 FAIL 不可被視覺降級；視覺只能補證據或提升為 REVIEW；UNKNOWN／REVIEW 不計入 PASS"}


def write_report(out, name, rows, meta, art):
    secs, tot = summarize(rows)
    fin = final_verdicts(rows)
    rep = {"name": name, "meta": meta, "summary": secs, "totals": tot, "final": fin,
           "note": "UNKNOWN 與 REVIEW 不計入 PASS；PASS 只代表在列出的檢查範圍內沒有發現問題", "results": rows}
    jsave(os.path.join(out, "report.json"), rep)
    L = [f"# Visual QA：{name}", "", f"- 模式：{meta.get('mode')}　profile：{meta.get('profile')}　canon：{meta.get('canon')}",
         f"- git {meta['version']['git_head']}（{meta['version']['branch']}）　{meta['version']['time']}",
         f"- Godot：{meta.get('godot')}　renderer：{meta.get('renderer')}　GPU：{meta.get('adapter')}",
         f"- 縮放：{meta.get('scale', 1)}　來源：{meta.get('scale_source', 'GLB 原尺寸')}",
         f"- 耗時：幾何 {meta.get('secs_geometry', 0):.1f} s、拍攝 {meta.get('secs_capture', 0):.1f} s、分析 {meta.get('secs_analyze', 0):.1f} s", "",
         "| 區段 | PASS | WARN | FAIL | UNKNOWN | REVIEW |", "|---|---:|---:|---:|---:|---:|"]
    for k, v in secs.items():
        L.append(f"| {SECTION_NAME.get(k, k)} | " + " | ".join(str(v.get(s, 0)) for s in VA.STATUSES) + " |")
    L.append("| **合計** | " + " | ".join(f"**{tot[s]}**" for s in VA.STATUSES) + " |")
    L += ["", f"## 最終判定：**{fin['overall']}**", "", "| 規則 | 幾何 | 視覺／審查證據 | 最終 |", "|---|---|---|---|"]
    for p in fin["per_rule"]:
        if p["final"] != "PASS" or p["evidence"]:
            L.append(f"| `{p['rule_id']}` | {p['geometry']} | {', '.join(p['evidence']) or '—'} | "
                     f"**{p['final']}**{'（硬性，鎖定）' if p['locked'] else ''} |")
    for st in ("FAIL", "REVIEW", "UNKNOWN", "WARN"):
        items = [r for r in rows if r["status"] == st]
        if not items:
            continue
        L += ["", f"## {st}（{len(items)}）"]
        for r in items:
            img = f"　圖：{', '.join(r['images'][:3])}" if r.get("images") else ""
            L.append(f"- `{r['rule_id']}` [{SECTION_NAME.get(r.get('section', 'geometry'))}] 物件 {r.get('object_ids')}："
                     f"{r.get('suggestion') or ''}　實測 {json.dumps(r.get('actual'), ensure_ascii=False)[:160]}{img}")
    L += ["", f"## PASS（{tot['PASS']}）", ", ".join(f"`{r['rule_id']}`" for r in rows if r["status"] == "PASS")]
    if art.get("sheets"):
        L += ["", "## 圖", *[f"- {s}" for s in art["sheets"]]]
    with open(os.path.join(out, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    return rep


# ─────────────────────────── 地圖（F） ───────────────────────────

def seg_x(p1, p2, p3, p4):
    d = (p2[0] - p1[0]) * (p4[1] - p3[1]) - (p2[1] - p1[1]) * (p4[0] - p3[0])
    if abs(d) < 1e-9:
        return None
    t = ((p3[0] - p1[0]) * (p4[1] - p3[1]) - (p3[1] - p1[1]) * (p4[0] - p3[0])) / d
    u = ((p3[0] - p1[0]) * (p2[1] - p1[1]) - (p3[1] - p1[1]) * (p2[0] - p1[0])) / d
    if 0 <= t <= 1 and 0 <= u <= 1:
        return (p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1]), p2[0] - p1[0], p2[1] - p1[1])
    return None


def road_junctions(layout, rg, cap=8):
    L = jload(res_abs(layout))
    roads = [(r["name"], r.get("class", "lane"), r["pts"]) for r in L.get("roads", []) + L.get("lanes", [])]
    out = []
    for i in range(len(roads)):
        for j in range(i + 1, len(roads)):
            for a in range(len(roads[i][2]) - 1):
                for b in range(len(roads[j][2]) - 1):
                    x = seg_x(roads[i][2][a], roads[i][2][a + 1], roads[j][2][b], roads[j][2][b + 1])
                    if x and rg[0] <= x[0] <= rg[2] and rg[1] <= x[1] <= rg[3]:
                        rank = (roads[i][1] == "main") + (roads[j][1] == "main")
                        out.append((rank, roads[i][0] + "×" + roads[j][0], x))
    out.sort(key=lambda t: -t[0])
    uniq = []
    for t in out:  # 同一對道路的多個線段交點、或 12 m 內的路口只取一個
        if any(t[1] == u[1] or math.hypot(t[2][0] - u[2][0], t[2][1] - u[2][1]) < 12 for u in uniq):
            continue
        uniq.append(t)
    views = []
    for rank, nm, (x, z, dx, dz) in uniq[:cap]:
        ln = math.hypot(dx, dz) or 1
        back = 9.0
        views.append({"name": nm.replace(" ", ""), "pos": [x - dx / ln * back, z - dz / ln * back], "look": [x + dx / ln * 20, z + dz / ln * 20]})
    return views, L


def map_mode(A, out):
    rg = vec(A["region"], 4)
    layout = A.get("layout", "res://maps/village_v2/layout_v2.json")
    views, L = road_junctions(layout, rg, int(A.get("max-views", 4)))
    lms = [x for x in str(A.get("landmarks", "")).split(",") if x]
    cap = os.path.join(out, "capture")
    job = {"out_dir": cap.replace("\\", "/"), "stage": "map", "scene": A["scene"], "region": rg, "layout": layout,
           "resolution": [int(x) for x in str(A.get("res", "1280x720")).split("x")], "settle_frames": int(A.get("settle", 12)),
           "player_views": views, "landmarks": lms, "taa": "taa" in A}
    t0 = time.time()
    man, secs, rc = run_capture(job, cap)
    if man is None:
        log(f"拍攝失敗（exit {rc}），見 {cap}/godot.log")
        return 2
    rows = []
    top = [e for e in man["images"] if e.get("kind") == "map_top"][0]
    im = Image.open(os.path.join(cap, top["file"])).convert("RGB")
    dr = ImageDraw.Draw(im)
    W, H = im.size
    s = (rg[3] - rg[1]) / H

    def P(x, z):
        return ((x - rg[0]) / s, (z - rg[1]) / s)

    for r in L.get("roads", []) + L.get("lanes", []):
        pts = [P(p[0], p[1]) for p in r["pts"]]
        dr.line(pts, fill=(255, 220, 0) if r.get("class") == "main" else (255, 255, 255), width=max(1, int(r["half_w"] * 2 / s / 3)))
    f = VA._font(14)
    labels = {"Landmarks/" + x["id"]: x.get("label", "") for x in L.get("landmarks", [])}
    for b in man.get("buildings", []):
        ed = b.get("road_edge_dist")
        lab = next((v for k, v in labels.items() if b["path"].startswith(k + "/")), "")
        gate = any(w in lab for w in ("鳥居", "門"))
        if "note" in b:
            st, sug = "UNKNOWN", b["note"]
        elif ed is None:
            st, sug = "UNKNOWN", "讀不到路網"
        else:
            st = "FAIL" if ed < -0.05 else "PASS"
            sug = f"腳印侵入 {b.get('road')} 路面 {-ed:.2f} m" if st == "FAIL" else ""
            if st == "FAIL" and gate:  # 門／鳥居本來就跨路：只有柱腳（各碰撞形狀）落在路面內才提醒，不判 FAIL
                st, sug = "WARN", f"{lab}跨路是設計；但柱腳形狀伸進 {b.get('road')} 路面 {-ed:.2f} m，確認通行寬度"
            if b.get("method") == "mesh_aabb":
                sug = (sug + "；" if sug else "") + "沒有碰撞形狀：用可見網格 AABB 量（偏保守）"
        rows.append(VA.vrow(f"MAP_ROAD:{b['path']}", "ROAD_INTRUSION", st, [b["path"]], {"edge_dist": ">=-0.05"},
                            {"edge_dist": ed, "road": b.get("road"), "at": b.get("road_at"), "label": lab,
                             "footprint_method": b.get("method"), "shapes": len(b.get("parts", []))},
                            method="arch_spatial_lib.road_intrusion（逐碰撞形狀；無碰撞→網格 AABB）",
                            suggestion=sug, section="map", images=["map_top_overlay.png"]))
        if b.get("parts") or b["footprint"]:
            col = {"FAIL": (255, 40, 40), "PASS": (60, 220, 90), "WARN": (255, 160, 0)}.get(st, (180, 180, 180))
            for poly in (b.get("parts") or [b["footprint"]]):
                dr.polygon([P(x, z) for x, z in poly], outline=col, width=2)
            if st in ("FAIL", "WARN"):
                cx, cz = b["pos"][0], b["pos"][2]
                dr.text(P(cx, cz), b["path"].split("/")[-1], fill=col, font=f)
    for v in views:
        dr.ellipse([*(np.array(P(*v["pos"])) - 6), *(np.array(P(*v["pos"])) + 6)], outline=(80, 160, 255), width=3)
        dr.line([P(*v["pos"]), P(*v["look"])], fill=(80, 160, 255), width=2)
    im.save(os.path.join(cap, "map_top_overlay.png"))
    pfiles = []
    for e in man["images"]:
        if e.get("kind") != "player":
            continue
        if e.get("status") == "UNKNOWN":
            rows.append(VA.vrow(f"MAP_VIEW:{e['name']}", "PLAYER_VIEW", "UNKNOWN", suggestion=e.get("reason"), section="map"))
            continue
        pfiles.append((e["file"], e["name"]))
        a = VA.img(cap, e["file"])
        r0 = VA.vrow(f"MAP_VIEW:{e['name']}", "PLAYER_VIEW", "PASS" if a.mean() > 4 else "UNKNOWN", actual={"mean": float(a.mean())},
                     method="玩家眼高 1.7 m、60°", section="map", images=[e["file"]], camera=e.get("camera"))
        rows.append(r0)
        for lm in e.get("landmarks", []):
            if lm.get("status") == "UNKNOWN":
                rows.append(VA.vrow(f"MAP_LANDMARK:{e['name']}:{lm['path']}", "LANDMARK", "UNKNOWN", [lm["path"]],
                                    suggestion=lm.get("reason"), section="map"))
                continue
            ida = VA.img(cap, lm["id"])
            solo = ida.max(axis=2) > 0
            n = int(solo.sum())
            if n < 0.0005 * solo.size:
                rows.append(VA.vrow(f"MAP_LANDMARK:{e['name']}:{lm['path']}", "LANDMARK", "PASS", [lm["path"]],
                                    actual={"in_view_px": n}, method="不在此視角視野內（只記錄）", section="map"))
                continue
            hid = VA.img(cap, lm["hidden"])
            seen = (np.abs(a - hid).max(axis=2) > VA.DIFF_TOL) & solo
            if lm.get("vis"):
                seen |= (VA.img(cap, lm["vis"]).max(axis=2) > 0) & solo  # 深度正確：其他幾何塗黑仍會擋
            vis = float(seen.sum() / n)
            st = "PASS" if vis >= 0.3 else "REVIEW"
            rows.append(VA.vrow(f"MAP_LANDMARK:{e['name']}:{lm['path']}", "LANDMARK", st, [lm["path"]], {"visible_ratio": ">=0.3"},
                                {"visible_ratio": round(vis, 3), "in_view_px": n}, method="地標隱藏差分 ∩ 地標 ID 遮罩",
                                suggestion="" if st == "PASS" else f"地標在視野內但只看得到 {vis:.0%}：確認遮擋物是否合理",
                                section="map", images=[e["file"]]))
    VA.sheet(cap, [x for x, _ in pfiles], [y for _, y in pfiles], "player_sheet.jpg", cols=2)
    meta = {"mode": "map", "region": rg, "version": version_info([A["scene"], layout]), "godot": man.get("godot"),
            "renderer": man.get("renderer"), "adapter": man.get("adapter"), "secs_capture": secs, "secs_analyze": time.time() - t0 - secs,
            "coverage": f"{len(man.get('buildings', []))} 棟（FastLane/*、Landmarks/*/Hero、Districts/**/B_*，中心在區域內）",
            "limits": ["只量路面侵入；朝向／退縮／立面線在快速通道 layout 檢查（逐棟）", "沒有碰撞形狀的建築腳印未知（UNKNOWN）"]}
    write_report(out, "map " + ",".join(str(int(x)) for x in rg), rows, meta,
                 {"sheets": [os.path.join(cap, "map_top_overlay.png"), os.path.join(cap, "player_sheet.jpg")]})
    return exit_code(rows)


def exit_code(rows):
    st = {r["status"] for r in rows} | {final_verdicts(rows)["overall"]}
    return 1 if "FAIL" in st else (3 if st & {"UNKNOWN", "REVIEW"} else 0)


# ─────────────────────────── main ───────────────────────────

def main():
    A = args()
    mode = A.get("mode", "full")
    name = A.get("name") or os.path.splitext(os.path.basename(str(A.get("glb") or A.get("node") or "scene").split(",")[0]))[0]
    out = os.path.abspath(A.get("out") or os.path.join(ROOT, "docs", "visual_qa", name))
    os.makedirs(out, exist_ok=True)
    if mode == "map":
        return map_mode(A, out)
    t0 = time.time()
    rows, G, spec = [], None, None
    if A.get("map"):
        spec = jload(A["map"])
    if mode in ("geometry-only", "full", "review-failures"):
        G = run_geometry(A, out)
        if G is None:
            rows.append(VA.vrow("GEOMETRY", "GEOMETRY", "UNKNOWN", method="arch_check",
                                suggestion="沒有 --blend＋--map 或 --scan：幾何驗證沒有跑", section="geometry"))
        elif "error" in G:
            rows.append(VA.vrow("GEOMETRY", "GEOMETRY", "UNKNOWN", suggestion=G["error"], section="geometry"))
        else:
            for r in G["report"]["results"]:
                rows.append(dict(r, section="geometry"))
            log(f"幾何：{G['report']['summary']}（{G['secs']:.1f} s）")
    if A.get("placement"):
        rows += placement_rows(A["placement"])
    bid = (G or {}).get("report", {}).get("building_id") if G and "report" in G else name
    prof_id, prof, canon = profile_for(A, bid or name)
    meta = {"mode": mode, "profile": prof_id, "canon": (canon or {}).get("id"), "canon_notes": (canon or {}).get("notes"),
            "scale": A.get("scale", 1), "scale_source": A.get("scale-source") or ("未指定（--scale-source）" if A.get("scale") else "GLB 原尺寸"),
            "secs_geometry": (G or {}).get("secs", 0.0) if G else 0.0}
    art = {}
    needs_capture = mode in ("visual-only", "full") or (mode == "review-failures" and G and "report" in G
                                                        and any(r["status"] != "PASS" for r in G["report"]["results"]))
    if mode == "review-failures" and not needs_capture:
        rows.append(VA.vrow("VISUAL", "CAPTURE", "PASS", method="review-failures", section="visual",
                            suggestion="幾何沒有非 PASS 項目，不拍局部圖"))
    if needs_capture and (A.get("glb") or A.get("scene")):
        cap = os.path.join(out, "capture")
        job = build_job(A, cap, mode, (G or {}).get("targets") if G and "report" in G else None,
                        (G or {}).get("fix_preview") if G and "report" in G else None)
        man, secs, rc = run_capture(job, cap)
        meta["secs_capture"] = secs
        if man is None or man.get("errors"):
            rows.append(VA.vrow("CAPTURE", "CAPTURE", "UNKNOWN", suggestion=f"拍攝失敗（exit {rc}）：{(man or {}).get('errors')}，見 {cap}/godot.log",
                                section="visual"))
        else:
            meta.update(godot=man.get("godot"), renderer=man.get("renderer"), adapter=man.get("adapter"), frame=man.get("frame"))
            t1 = time.time()
            vr, art = analyze(A, cap, man, G, prof_id, prof, canon, spec)
            rows += vr
            sheets = []
            if art["view_files"]:
                sheets.append(VA.sheet(cap, [f for f, _ in art["view_files"]], [l for _, l in art["view_files"]], "views_sheet.jpg"))
            if art["focus_files"]:
                sheets.append(VA.sheet(cap, [f for f, _ in art["focus_files"]], [l for _, l in art["focus_files"]], "focus_sheet.jpg", cols=2))
            if art["fix_files"]:
                pairs = []
                for before, after, lb in art["fix_files"]:
                    pairs += [(before, "修正前 " + lb), (after, "修正後（預覽，未寫入）" + lb)]
                sheets.append(VA.sheet(cap, [f for f, _ in pairs], [l for _, l in pairs], "fix_sheet.jpg", cols=2))
            art["sheets"] = [os.path.join(cap, s) for s in sheets if s]
            req = review_request(out, cap, man, G, rows, prof_id, prof, art)
            if A.get("review"):
                rows += merge_review(jload(A["review"]), cap, man, (G or {}).get("report", {}).get("results", []) if G and "report" in G else [], G)
            meta["secs_analyze"] = time.time() - t1
            meta["review_request"] = os.path.join(out, "review_request.json")
            _ = req
    elif needs_capture:
        rows.append(VA.vrow("CAPTURE", "CAPTURE", "UNKNOWN", suggestion="沒有 --glb 或 --scene：無法拍攝", section="visual"))
    meta["version"] = version_info([A.get("blend"), A.get("map"), A.get("scene"), A.get("ref"), A.get("placement")]
                                   + str(A.get("glb", "")).split(","))
    meta["secs_total"] = time.time() - t0
    rep = write_report(out, name, rows, meta, art)
    log(f"{name}：{rep['totals']} → {out}\\report.md（{meta['secs_total']:.1f} s）")
    return exit_code(rows)


if __name__ == "__main__":
    sys.exit(main())
