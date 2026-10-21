"""快速通道 × arch_spatial 整合測試（P1-A 匯入一致性、P1-C 道路排列）。

真的跑 place_building.sh（village_v2 正式場景，一律 --dry --no-shots：不寫場景、不截圖），
測試資產＝test_arch_spatial.py 匯出的 arch_axis_test.glb（Parent＋非均勻＋負縮放＋正面標記）。
跑完刪掉 assets/village_v2/fastlane/archtest/ 與 docs/fastlane/archtest/。

  python godot/tools/fastlane/test_fastlane_arch.py [--keep]
"""
import json
import math
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GODOT_DIR = os.path.join(ROOT, "godot")
BLENDER = os.environ.get("BLENDER", r"D:/Blender/blender-5.2.1-windows-x64/blender.exe")
GODOT = os.environ.get("GODOT", r"D:/Godot/Godot_v4.7.2-stable_win64_console.exe")
TMP = os.path.join(os.environ.get("TMPDIR", os.path.join(ROOT, "work")), "fastlane_arch_test")
ID = "archtest"
ASSET_DIR = os.path.join(GODOT_DIR, "assets", "village_v2", "fastlane", ID)
DOC_DIR = os.path.join(ROOT, "docs", "fastlane", ID)
RESULTS = []


def check(label, got, want, detail=""):
    ok = got == want
    RESULTS.append(ok)
    print(f"{'ok ' if ok else 'BAD'} {label}: got {got} want {want} {detail}", flush=True)


def run_fastlane(args, label):
    t = time.time()
    cmd = ["bash", "godot/tools/fastlane/place_building.sh", f"--id={ID}", "--dry", "--no-shots"] + args
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    dt = time.time() - t
    lines = [l for l in p.stdout.splitlines() if l.startswith("[FASTLANE]")]
    res_path = os.path.join(DOC_DIR, "result.json")
    res = json.load(open(res_path, encoding="utf-8")) if os.path.exists(res_path) else {}
    print(f"--- {label}  ({dt:.1f} s, exit {p.returncode})")
    for l in lines:
        if any(k in l for k in ("consistency", "layout", "匯入一致性", "FAIL", "SCRIPT ERROR")):
            print("   ", l[:260])
    if "SCRIPT ERROR" in p.stdout + p.stderr:
        print(p.stdout[-3000:], p.stderr[-2000:])
    os.remove(res_path) if os.path.exists(res_path) else None
    return res, dt


def rows(res, prefix):
    return [r for r in res.get("arch", {}).get("results", []) if r["rule_id"].startswith(prefix)]


def status(res, rid):
    for r in res.get("arch", {}).get("results", []):
        if r["rule_id"] == rid:
            return r["status"]
    return None


def main():
    keep = "--keep" in sys.argv
    os.makedirs(TMP, exist_ok=True)
    # 1. 測試 GLB＋Blender 期望值
    subprocess.run([BLENDER, "-b", "--factory-startup", "--python", os.path.join(ROOT, "tools", "blender", "test_arch_spatial.py"),
                    "--", "--no-perf", f"--tmp={TMP}", f"--glb-out={TMP}"], check=True, capture_output=True)
    glb = os.path.join(TMP, "arch_axis_test.glb")
    expect = os.path.join(TMP, "arch_axis_test.expect.json")
    # 2. 放在 MainStreet 旁（layout 中心線），正面（模型 +Z）朝路
    L = json.load(open(os.path.join(GODOT_DIR, "maps", "village_v2", "layout_v2.json"), encoding="utf-8"))
    road = next(r for r in L["roads"] if r["name"] == "MainStreet")
    a, b = road["pts"][2], road["pts"][3]
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    t = (b[0] - a[0], b[1] - a[1]); tl = math.hypot(*t); t = (t[0] / tl, t[1] / tl)
    n = (-t[1], t[0])
    off = road["half_w"] + 5.0
    at = (mid[0] + n[0] * off, mid[1] + n[1] * off)
    to_road = (-n[0], -n[1])
    yaw = math.degrees(math.atan2(to_road[0], to_road[1]))
    base = [f"--glb={glb}", f"--at={at[0]:.2f},{at[1]:.2f}"]
    print(f"MainStreet 段 {a}→{b}，放在 {at[0]:.1f},{at[1]:.1f}，yaw {yaw:.1f}°（正面朝路）")
    times = []

    # C1 organic、正面朝路、Blender 期望值 → consistency PASS、layout PASS
    res, dt = run_fastlane(base + [f"--yaw={yaw:.2f}", f"--expect={expect}", "--layout=organic"], "C1 organic 朝路＋期望值")
    times.append(dt)
    ck = res.get("checks", {})
    check("C1 consistency（GLB↔匯入↔Blender↔放置鏈）", ck.get("consistency", {}).get("result"), "PASS",
          ck.get("consistency", {}).get("detail", "")[:200])
    check("C1 layout organic 朝路", ck.get("layout", {}).get("result"), "PASS", ck.get("layout", {}).get("detail", "")[:200])
    check("C1 匯入節點 4 個逐一比對（含負縮放 mirror）", sorted(r["object_ids"][0] for r in rows(res, "glb_vs_import:")),
          ["beam", "front_marker", "mirror", "post"])
    check("C1 放置鏈逐節點比對", len(rows(res, "placed_world:")), 4)
    check("C1 Blender→匯入 mirror det<0 保留", next((r["actual"].get("det_got") for r in rows(res, "blender_vs_import:mirror")), None), -1.0)
    check("C1 原有三項仍在", sorted(k for k in ck if k in ("ground", "overlap", "access")), ["access", "ground", "overlap"])

    # C2 structured 背對道路 → layout FAIL
    res, dt = run_fastlane(base + [f"--yaw={yaw + 180:.2f}", "--layout=structured"], "C2 structured 背對")
    times.append(dt)
    check("C2 structured 背對道路 → layout FAIL", res.get("checks", {}).get("layout", {}).get("result"), "FAIL",
          res.get("checks", {}).get("layout", {}).get("detail", "")[:200])
    check("C2 有 FAIL → 不會寫入（dry 本來就不寫；_passes 判 FAIL）", res.get("written"), False)

    # C3 landmark：主軸對準 40 m 外的目標（故意不朝路）→ PASS；同一次 tampered 期望值 → consistency FAIL
    side_yaw = yaw + 70.0
    tgt = (at[0] + math.sin(math.radians(side_yaw)) * 40, at[1] + math.cos(math.radians(side_yaw)) * 40)
    bad = json.load(open(expect, encoding="utf-8"))
    bad["nodes"]["ghost_post"] = dict(bad["nodes"]["post"])
    bad["nodes"]["beam"]["max"][1] += 0.25
    bad_path = os.path.join(TMP, "tampered.expect.json")
    json.dump(bad, open(bad_path, "w", encoding="utf-8"))
    res, dt = run_fastlane(base + [f"--yaw={side_yaw:.2f}", "--layout=landmark", f"--axis-target={tgt[0]:.2f},{tgt[1]:.2f}",
                                   f"--expect={bad_path}"], "C3 landmark＋竄改期望值")
    times.append(dt)
    check("C3 landmark 主軸對準（不朝路也 PASS）", status(res, "layout:landmark_axis"), "PASS")
    check("C3 期望值多了不存在的節點 → FAIL（不當 PASS）", status(res, "blender_vs_import:ghost_post"), "FAIL")
    check("C3 期望值 beam 高 0.25 m → FAIL", status(res, "blender_vs_import:beam"), "FAIL")
    check("C3 consistency 總結 FAIL", res.get("checks", {}).get("consistency", {}).get("result"), "FAIL")

    # C4 landmark 沒給主軸參考 → UNKNOWN（不猜）
    res, dt = run_fastlane(base + [f"--yaw={side_yaw:.2f}", "--layout=landmark"], "C4 landmark 無主軸")
    times.append(dt)
    check("C4 landmark 無主軸參考 → layout UNKNOWN", res.get("checks", {}).get("layout", {}).get("result"), "UNKNOWN")

    # C5 匯入異常：改 .glb.import 的 root_scale → 重新匯入 → GLB↔匯入 FAIL（縮放）
    imp = os.path.join(ASSET_DIR, f"{ID}.glb.import")
    txt = open(imp, encoding="utf-8").read()
    assert "nodes/root_scale=1.0" in txt, "import 檔沒有 nodes/root_scale=1.0"
    open(imp, "w", encoding="utf-8").write(txt.replace("nodes/root_scale=1.0", "nodes/root_scale=1.5"))
    subprocess.run([GODOT, "--headless", "--path", GODOT_DIR, "--import"], capture_output=True)
    res, dt = run_fastlane(base + [f"--yaw={yaw:.2f}"], "C5 root_scale=1.5 匯入異常")
    times.append(dt)
    c5 = rows(res, "glb_vs_import:")
    check("C5 匯入縮放異常 → glb_vs_import 全部 FAIL", sorted({r["status"] for r in c5}), ["FAIL"],
          (c5[0]["suggestion"][:160] if c5 else ""))
    check("C5 consistency 總結 FAIL", res.get("checks", {}).get("consistency", {}).get("result"), "FAIL")

    print(f"\n[FASTLANE-ARCH-TEST] {sum(RESULTS)}/{len(RESULTS)} ok；每次快速通道 {', '.join(f'{x:.0f}' for x in times)} s")
    if not keep:
        shutil.rmtree(ASSET_DIR, ignore_errors=True)
        shutil.rmtree(DOC_DIR, ignore_errors=True)
        print("已清除", ASSET_DIR, DOC_DIR)
    sys.exit(0 if all(RESULTS) else 1)


if __name__ == "__main__":
    main()
