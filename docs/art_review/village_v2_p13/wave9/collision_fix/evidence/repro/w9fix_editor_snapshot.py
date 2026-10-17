"""W9 FIX 最終驗收：真の編輯器テストの前後で、プロジェクトの状態を記録・比較する（読むだけ。拋棄式副本の作成／削除だけ書く）。
  python w9fix_editor_snapshot.py snap <name>      → editor/state_<name>.json
  python w9fix_editor_snapshot.py copy             → godot/_w9fix_disposable/village_v2_copy.tscn（header の uid を外す）
  python w9fix_editor_snapshot.py diff <a> <b>     → 2 つの state の差
"""
import hashlib, json, os, re, subprocess, sys
from pathlib import Path

REPO = Path("D:/神社/shrine")
GD = REPO / "godot"
OUT = REPO / "work/w9_collision_fix/editor"
OUT.mkdir(parents=True, exist_ok=True)
SRC = GD / "maps/village_v2/village_v2.tscn"
DISP_DIR = GD / "_w9fix_disposable"
COPY = DISP_DIR / "village_v2_copy.tscn"
KEY = [GD / "project.godot", SRC, GD / "maps/village_v2/gen/arch_w9r2_p13.scn",
       GD / "maps/village_v2/scripts_p13/arch_w9r2.gd", GD / "assets/village_v2/w9r2_arch/src/collision_fit.json"]


def md5(p):
    return hashlib.md5(p.read_bytes()).hexdigest() if p.exists() else None


def snap(name):
    st = {"key": {str(p.relative_to(REPO)): md5(p) for p in KEY}}
    imp = {}
    for root, dirs, files in os.walk(GD):
        dirs[:] = [d for d in dirs if d not in (".godot", ".git")]
        for f in files:
            if f.endswith(".import") or f.endswith(".uid"):
                p = Path(root) / f
                imp[str(p.relative_to(REPO))] = md5(p)
    st["import_uid_files"] = imp
    por = subprocess.run(["git", "-C", str(REPO), "-c", "core.quotepath=false", "status", "--porcelain=v1", "-uall"],
                         capture_output=True, text=True, encoding="utf-8").stdout
    st["git_status"] = sorted(l for l in por.splitlines() if "_w9fix_disposable" not in l and "tests/test_w9fix_editor" not in l)
    st["git_index_raw_md5"] = hashlib.md5(subprocess.run(["git", "-C", str(REPO), "-c", "core.quotepath=false", "diff", "--cached", "--raw"],
                                                          capture_output=True).stdout).hexdigest()
    st["copy_md5"] = md5(COPY)
    (OUT / f"state_{name}.json").write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")
    print(name, "key", st["key"], "imports/uids", len(imp), "git lines", len(st["git_status"]), "index", st["git_index_raw_md5"], "copy", st["copy_md5"])


def copy():
    DISP_DIR.mkdir(exist_ok=True)
    (DISP_DIR / ".gdignore").unlink(missing_ok=True)
    txt = SRC.read_text(encoding="utf-8")
    first, rest = txt.split("\n", 1)
    first2 = re.sub(r'\s+uid="uid://[^"]+"', "", first)
    COPY.write_text(first2 + "\n" + rest, encoding="utf-8", newline="")
    (OUT / "copy_original.tscn").write_text(first2 + "\n" + rest, encoding="utf-8", newline="")
    print("header", first, "->", first2, "bytes", COPY.stat().st_size)


def diff(a, b):
    A = json.loads((OUT / f"state_{a}.json").read_text(encoding="utf-8"))
    B = json.loads((OUT / f"state_{b}.json").read_text(encoding="utf-8"))
    for k in A["key"]:
        if A["key"][k] != B["key"].get(k):
            print("KEY CHANGED", k)
    ia, ib = A["import_uid_files"], B["import_uid_files"]
    ch = [k for k in set(ia) | set(ib) if ia.get(k) != ib.get(k)]
    print("import/uid changed", len(ch), sorted(ch)[:40])
    ga, gb = set(A["git_status"]), set(B["git_status"])
    print("git status -", sorted(ga - gb)[:40])
    print("git status +", sorted(gb - ga)[:40])
    print("index same", A["git_index_raw_md5"] == B["git_index_raw_md5"])


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "snap":
        snap(sys.argv[2])
    elif cmd == "copy":
        copy()
    elif cmd == "diff":
        diff(sys.argv[2], sys.argv[3])
