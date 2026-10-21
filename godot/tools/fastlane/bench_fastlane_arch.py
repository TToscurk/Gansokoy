"""快速通道效能對照：HEAD 版 place_building.gd vs 目前版本（同一資產、同一位置，--dry --no-shots，各跑 2 次）。
跑完刪掉暫存的 HEAD 副本與測試資產。  python godot/tools/fastlane/bench_fastlane_arch.py"""
import os
import re
import shutil
import subprocess
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GD = os.path.join(ROOT, "godot")
GODOT = os.environ.get("GODOT", r"D:/Godot/Godot_v4.7.2-stable_win64_console.exe")
TMP = os.path.join(os.environ.get("TMPDIR", os.path.join(ROOT, "work")), "fastlane_arch_test")
ID = "archperf"
HEAD_COPY = os.path.join(GD, "tools", "fastlane", "_place_building_head.gd")


def run(script, extra):
    t = time.time()
    p = subprocess.run([GODOT, "--path", GD, "--resolution", "1280x720", "--script", script, "--",
                        f"--id={ID}", "--at=260.20,12.70", "--yaw=-108.4", "--dry", "--no-shots"] + extra,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    secs = re.findall(r"完成：written=\S+\s+\(([\d.]+)s\)", p.stdout)
    return time.time() - t, float(secs[-1]) if secs else None, p.returncode


def main():
    glb = os.path.join(TMP, "arch_axis_test.glb")
    assert os.path.exists(glb), "先跑 test_fastlane_arch.py --keep 或 test_arch_spatial.py --glb-out"
    subprocess.run(["bash", "godot/tools/fastlane/place_building.sh", f"--glb={glb}", f"--id={ID}", "--at=260.20,12.70",
                    "--dry", "--no-shots"], cwd=ROOT, capture_output=True)  # 複製＋匯入（不計時）
    head = subprocess.run(["git", "show", "HEAD:godot/tools/fastlane/place_building.gd"], cwd=ROOT, capture_output=True).stdout
    open(HEAD_COPY, "wb").write(head)
    try:
        rows = []
        for label, script, extra in (("HEAD", "res://tools/fastlane/_place_building_head.gd", []),
                                     ("now", "res://tools/fastlane/place_building.gd", []),
                                     ("now --layout=off", "res://tools/fastlane/place_building.gd", ["--layout=off"]),
                                     ("now structured", "res://tools/fastlane/place_building.gd", ["--layout=structured"])):
            for k in range(2):
                wall, inner, rc = run(script, extra)
                rows.append((label, k, wall, inner, rc))
                print(f"{label:18} run{k}: wall {wall:.1f} s, script {inner} s, exit {rc}", flush=True)
    finally:
        os.remove(HEAD_COPY)
        uid = HEAD_COPY + ".uid"
        if os.path.exists(uid):
            os.remove(uid)
        shutil.rmtree(os.path.join(GD, "assets", "village_v2", "fastlane", ID), ignore_errors=True)
        shutil.rmtree(os.path.join(ROOT, "docs", "fastlane", ID), ignore_errors=True)


if __name__ == "__main__":
    main()
