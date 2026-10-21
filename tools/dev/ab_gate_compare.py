"""村莊 gate 前後版本 A/B 對照（只換指定檔案，其他一切相同）。

  python tools/dev/ab_gate_compare.py --base=<git rev> --paths=a,b,... [--tags=HERO,PLACE] [--out=<dir>]

- 指令直接從 godot/tools/run_village_v2_regression.sh 的 `run "…" TAG 參數…` 行解析（同一份參數、同一個 Godot）。
- 順序 B（現況）→ A（--paths 換成 --base 版本；base 沒有的檔案暫時移走）→ B（再跑一次，抓不穩定／漂移）。
- 每輪前後對 --watch 目錄做（路徑、大小、mtime）快照。作廢（INVALID）只看「會影響結果」的漂移：
  場景／資產目錄（--scene-dirs）＋ gate 腳本的靜態載入鏈（preload／load／extends 遞迴）；其他檔案的變動列為 unrelated。
- 比對輸出行前先遮掉耗時數字（「13537 ms」「85.9 s」），否則每輪必然不同。
- --from-logs：不重跑，直接用 --out 裡上次三輪的 log＋快照重新判定（工具修正後重算用）。
- 換檔一律 try/finally 還原，並以 sha256 確認還原後與開始前一致。不碰 --paths 以外的任何檔案。
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GD = os.path.join(ROOT, "godot")
REG = os.path.join(GD, "tools", "run_village_v2_regression.sh")
GODOT = os.environ.get("GODOT") or "D:/Godot/Godot_v4.7.2-stable_win64_console.exe"


def args():
    return dict(a.lstrip("-").partition("=")[::2] for a in sys.argv[1:])


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


TIMING = re.compile(r"\d+(?:\.\d+)? ?(?:ms|s)\b")


def norm(lines):
    return sorted(TIMING.sub("<t>", ln) for ln in lines)


def closure(scripts):
    """gate 腳本的靜態載入鏈（res:// 路徑）。"""
    seen = set()

    def walk(p):
        if p in seen:
            return
        seen.add(p)
        ap = os.path.join(GD, p[6:]) if p.startswith("res://") else p
        try:
            txt = open(ap, encoding="utf-8", errors="replace").read()
        except OSError:
            return
        for m in re.finditer(r'(?:preload|load)\(\s*"(res://[^"]+\.gd)"|extends\s+"(res://[^"]+\.gd)"', txt):
            walk(m.group(1) or m.group(2))
    for s in scripts:
        walk(s)
    return {"godot/" + p[6:] for p in seen}


def relevant(drift, deps, scene_dirs):
    out = []
    for f in drift:
        g = f[:-4] if f.endswith(".uid") else f
        if g in deps or any(f.startswith(d.rstrip("/") + "/") or f == d for d in scene_dirs):
            out.append(f)
    return out


def gate_cmds(tags):
    out = {}
    for ln in open(REG, encoding="utf-8"):
        m = re.match(r'^run\s+"[^"]*"\s+(\w+)\s+(.*)$', ln.strip())
        if m and m.group(1) in tags and m.group(1) not in out:
            out[m.group(1)] = m.group(2).split()
    return out


def snapshot(paths, skip):
    snap = {}
    for base in paths:
        ap = os.path.join(ROOT, base)
        if os.path.isfile(ap):
            st = os.stat(ap)
            snap[base] = (st.st_size, st.st_mtime_ns)
            continue
        for dp, dn, fn in os.walk(ap):
            dn[:] = [d for d in dn if d not in (".godot", "__pycache__")]
            for f in fn:
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, ROOT).replace("\\", "/")
                if rel in skip:
                    continue
                st = os.stat(p)
                snap[rel] = (st.st_size, st.st_mtime_ns)
    return snap


def diff_snap(a, b):
    return sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))


def run_gates(cmds, tag_label, out):
    res = {}
    for tag, argv in cmds.items():
        t = time.time()
        p = subprocess.run([GODOT, *argv], cwd=GD, capture_output=True, text=True, encoding="utf-8", errors="replace")
        txt = p.stdout + p.stderr
        open(os.path.join(out, f"{tag_label}_{tag}.log"), "w", encoding="utf-8").write(txt)
        lines = [ln.strip() for ln in txt.splitlines() if ln.startswith(f"[{tag}]")]
        fails = norm(ln for ln in lines if " FAIL" in ln or "REVIEW" in ln)
        summary = [ln for ln in lines if "結果" in ln]
        res[tag] = {"exit": p.returncode, "secs": round(time.time() - t, 1), "summary": summary, "fail_lines": fails,
                    "script_errors": sum(1 for ln in txt.splitlines() if "SCRIPT ERROR" in ln or "Parse Error" in ln)}
        print(f"[AB] {tag_label} {tag}: exit {p.returncode}, {len(fails)} FAIL/REVIEW 行, {res[tag]['secs']} s; {summary[-1:] }", flush=True)
    return res


def main():
    A = args()
    base = A["base"]
    paths = [p for p in A["paths"].split(",") if p]
    tags = A.get("tags", "HERO,PLACE").split(",")
    watch = A.get("watch", "godot/maps/village_v2,godot/assets/village_v2,godot/tools,godot/project.godot").split(",")
    out = os.path.abspath(A.get("out") or os.path.join(os.environ.get("LOCALAPPDATA", ROOT), "hermes", "cache", "scratch", "ab_gate"))
    os.makedirs(out, exist_ok=True)
    cmds = gate_cmds(tags)
    scene_dirs = A.get("scene-dirs", "godot/maps/village_v2,godot/assets/village_v2,godot/project.godot").split(",")
    deps = closure([a for argv in cmds.values() for i, a in enumerate(argv) if i and argv[i - 1] == "--script"])
    if "from-logs" in A:
        return reanalyze(out, cmds, tags, deps, scene_dirs)
    missing = [t for t in tags if t not in cmds]
    if missing:
        print(f"[AB] 回歸腳本裡找不到 tag：{missing}")
        return 2
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    bk = os.path.join(out, "backup")
    os.makedirs(bk, exist_ok=True)
    orig = {}
    for p in paths:
        ap = os.path.join(ROOT, p)
        if os.path.exists(ap):
            orig[p] = sha(ap)
            dst = os.path.join(bk, p.replace("/", "__"))
            shutil.copy2(ap, dst)
    base_blobs = {}
    for p in paths:
        r = subprocess.run(["git", "show", f"{base}:{p}"], cwd=ROOT, capture_output=True)
        base_blobs[p] = r.stdout if r.returncode == 0 else None
    skip = set(paths)
    report = {"base": base, "head": head, "paths": paths, "cmds": cmds, "godot": GODOT, "rounds": []}
    s0 = snapshot(watch, skip)
    report["rounds"].append({"label": "B1", "results": run_gates(cmds, "B1", out)})
    s1 = snapshot(watch, skip)
    try:
        for p in paths:
            ap = os.path.join(ROOT, p)
            if base_blobs[p] is None:
                if os.path.exists(ap):
                    os.remove(ap)
            else:
                with open(ap, "wb") as f:
                    f.write(base_blobs[p])
        report["rounds"].append({"label": "A", "results": run_gates(cmds, "A", out)})
    finally:
        for p in paths:
            ap = os.path.join(ROOT, p)
            if p in orig:
                shutil.copy2(os.path.join(bk, p.replace("/", "__")), ap)
            elif os.path.exists(ap):
                os.remove(ap)
        restored = all(sha(os.path.join(ROOT, p)) == h for p, h in orig.items()) and \
            all(not os.path.exists(os.path.join(ROOT, p)) for p in paths if p not in orig)
        report["restored"] = restored
        print(f"[AB] 還原 {'OK' if restored else '失敗！'}（{len(orig)} 檔 sha256 比對）", flush=True)
    s2 = snapshot(watch, skip)
    report["rounds"].append({"label": "B2", "results": run_gates(cmds, "B2", out)})
    s3 = snapshot(watch, skip)
    drift = {"B1": diff_snap(s0, s1), "A": diff_snap(s1, s2), "B2": diff_snap(s2, s3)}
    report["drift"] = drift
    json.dump(report, open(os.path.join(out, "ab_report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return judge(report, out, tags, deps, scene_dirs)


def reanalyze(out, cmds, tags, deps, scene_dirs):
    report = json.load(open(os.path.join(out, "ab_report.json"), encoding="utf-8"))
    for rnd in report["rounds"]:
        for t in tags:
            txt = open(os.path.join(out, f"{rnd['label']}_{t}.log"), encoding="utf-8").read()
            lines = [ln.strip() for ln in txt.splitlines() if ln.startswith(f"[{t}]")]
            rnd["results"][t]["fail_lines"] = norm(ln for ln in lines if " FAIL" in ln or "REVIEW" in ln)
    print("[AB] --from-logs：用既有三輪 log 重新判定（遮掉耗時、只看載入鏈與場景目錄的漂移）")
    return judge(report, out, tags, deps, scene_dirs)


def judge(report, out, tags, deps, scene_dirs):
    drift = report["drift"]
    rel = {k: relevant(v, deps, scene_dirs) for k, v in drift.items()}
    report["gate_closure"] = sorted(deps)
    report["relevant_drift"] = rel
    report["unrelated_drift"] = {k: sorted(set(v) - set(rel[k])) for k, v in drift.items()}
    valid = not any(rel.values()) and report["restored"]
    verdict = {}
    for t in tags:
        b1, a, b2 = (r["results"][t] for r in report["rounds"])
        same_b = b1["fail_lines"] == b2["fail_lines"] and b1["exit"] == b2["exit"]
        same_ab = a["fail_lines"] == b1["fail_lines"] and a["exit"] == b1["exit"]
        verdict[t] = ("INVALID（場景／gate 在對照途中被改動）" if not valid else
                      "UNSTABLE（B 兩輪不同，無法判定）" if not same_b else
                      "SAME（換掉 --paths 不影響結果：失敗與這些檔案無關）" if same_ab else
                      "DIFFERENT（--paths 改變了結果）")
    report["verdict"] = verdict
    report["valid"] = valid
    json.dump(report, open(os.path.join(out, "ab_report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"[AB] gate 載入鏈 {len(deps)} 個腳本：{sorted(deps)}")
    for t, v in verdict.items():
        print(f"[AB] {t}: {v}")
    if any(rel.values()):
        print("[AB] 影響結果的漂移：", {k: v[:10] for k, v in rel.items() if v})
    un = report["unrelated_drift"]
    if any(un.values()):
        print("[AB] 不影響結果的漂移（不在載入鏈／場景目錄）：", sum(len(v) for v in un.values()), "檔，例：",
              sorted({x for v in un.values() for x in v})[:6])
    return 0 if valid else 2


if __name__ == "__main__":
    sys.exit(main())
