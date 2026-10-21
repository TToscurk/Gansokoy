#!/usr/bin/env python
"""test_gd_check — gd_check 快取／相依／併發情境測試（隔離的暫存專案，不碰遊戲腳本）。

用法
    python tools/dev/test_gd_check.py                         # 測試目前的 tools/dev/gd_check.py
    python tools/dev/test_gd_check.py --module <舊版.py>       # 對舊版跑同一套情境（修改前後對照；新功能情境會標 N/A）
    python tools/dev/test_gd_check.py --only E,F              # 只跑某些群組

情境群組：A 改檔／B 相依檔改動／C autoload 改動／D project.godot／E 資源增刪改／F 併發修改／G 快取策略
          K class_name 快取／H 變動偵測與反向依賴（暫存 git repo）／V 版本鎖定
exit code：0 全部符合預期；1 有不符。
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TAB = "\t"

PROJECT_GODOT = """config_version=5

[application]

config/name="gd_check_test"
config/features=PackedStringArray("4.7")

[autoload]

Svc="*res://svc.gd"
"""
FILES = {
    "svc.gd": f"extends Node\nfunc ping() -> int:\n{TAB}return 1\n",
    "b.gd": f"class_name BHelper\nextends RefCounted\nfunc val() -> int:\n{TAB}return 1\n",
    "a.gd": f"extends Node\nconst B = preload(\"res://b.gd\")\nfunc f() -> int:\n{TAB}var b := B.new()\n{TAB}return b.val() + Svc.ping()\n",
    "c.gd": f"extends Node\nfunc g(x: BHelper) -> int:\n{TAB}return x.val()\n",
    "z.gd": f"extends Node\nfunc z() -> int:\n{TAB}return 0\n",
    "a2.gd": f"extends Node\nconst D = preload(\"res://data.res\")\nfunc f():\n{TAB}return D\n",
    "a3.gd": f"extends Node\nconst S = preload(\"res://s.tscn\")\nfunc f():\n{TAB}return S\n",
    "a4.gd": f"extends Node\nconst T = preload(\"res://t.tres\")\nfunc f():\n{TAB}return T\n",
    "a5.gd": f"extends Node\nfunc f():\n{TAB}return load(\"res://data.res\")\n",   # 只有執行期 load()，不是編譯期相依
    "s.tscn": "[gd_scene format=3]\n\n[node name=\"S\" type=\"Node\"]\n",
    "t.tres": "[gd_resource type=\"Resource\" format=3]\n\n[resource]\n",
    "make_res.gd": f"extends SceneTree\nfunc _init() -> void:\n{TAB}ResourceSaver.save(Resource.new(), \"res://data.res\")\n{TAB}quit()\n",
}

RESULTS: list[tuple[str, bool, str]] = []
NA: list[str] = []


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location("gdc_under_test", path)
    m = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(path.parent))
    spec.loader.exec_module(m)
    return m


def bind(mod, proj: Path, repo: Path | None = None) -> None:
    if hasattr(mod, "set_project"):
        mod.set_project(proj)
    else:                                    # 舊版：只有全域變數
        mod.PROJ = proj.resolve()
        mod.CACHE_FILE = mod.PROJ / ".godot" / "gd_check_cache.json"
    if repo is not None:
        mod.REPO = repo.resolve()


def ok(group: str, name: str, cond: bool, observed: str = "") -> None:
    RESULTS.append((group, cond, f"[{group}] {'PASS' if cond else 'FAIL'}  {name}" + (f"   | {observed}" if observed else "")))
    print(RESULTS[-1][2], flush=True)


def na(group: str, name: str) -> None:
    NA.append(name)
    print(f"[{group}] N/A   {name}（此版本沒有這個功能）", flush=True)


def build_project(mod, root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / "project.godot").write_text(PROJECT_GODOT, encoding="utf-8", newline="\n")
    for n, body in FILES.items():
        (root / n).write_text(body, encoding="utf-8", newline="\n")
    g = mod.resolve_godot() if hasattr(mod, "resolve_godot") else {"path": mod.find_godot()}
    subprocess.run([g["path"], "--headless", "--path", str(root), "--script", "res://make_res.gd"], capture_output=True, timeout=120)
    if not (root / "data.res").exists():
        raise SystemExit("測試準備失敗：無法產生 data.res")
    (root / "make_res.gd").unlink()
    subprocess.run([g["path"], "--headless", "--path", str(root), "--import"], capture_output=True, timeout=180)   # 建立 class 快取


def chk(mod, root: Path, names: list[str], cache: bool = True) -> dict[str, dict]:
    res = mod.run_checks([root / n for n in names], 2, 60, cache)
    return {Path(r["path"]).name: r for r in res}


def put(root: Path, name: str, body: str) -> None:
    (root / name).write_text(body, encoding="utf-8", newline="\n")
    time.sleep(0.02)


def hooked(mod, trigger: str, action):
    """在「檢查 trigger 這支腳本的 godot 呼叫剛結束」時執行 action（模擬另一個 Session 同時改檔）。"""
    orig = mod.run_godot

    def run(godot, args, timeout):
        rc, out = orig(godot, args, timeout)
        if "--check-only" in args and any(a.endswith(trigger) for a in args):
            action()
        return rc, out
    mod.run_godot = run
    return lambda: setattr(mod, "run_godot", orig)


# ─────────────────────────── 群組 ───────────────────────────

def group_A(mod, root):
    r1 = chk(mod, root, ["a.gd"])["a.gd"]
    r2 = chk(mod, root, ["a.gd"])["a.gd"]
    ok("A", "第一次 PASS、第二次未改動 → 用快取", r1["status"] == "PASS" and not r1["cached"] and r2["status"] == "PASS" and r2["cached"], f"{r1['status']}/{r2['status']} cached={r2['cached']}")
    orig = (root / "a.gd").read_text(encoding="utf-8")
    put(root, "a.gd", orig.replace("b.val()", "b.val(") )   # 破壞語法
    r3 = chk(mod, root, ["a.gd"])["a.gd"]
    ok("A", "改壞 a.gd → 快取失效、重查得 FAIL", r3["status"] == "FAIL" and not r3["cached"], f"{r3['status']} cached={r3['cached']}")
    put(root, "a.gd", orig)
    r4 = chk(mod, root, ["a.gd"])["a.gd"]
    ok("A", "改回原內容 → PASS（不被舊的 FAIL 擋住）", r4["status"] == "PASS", f"{r4['status']} cached={r4['cached']}")


def group_B(mod, root):
    chk(mod, root, ["a.gd", "c.gd"])
    cached = chk(mod, root, ["a.gd", "c.gd"])
    ok("B", "前置：a.gd／c.gd 都已快取 PASS", all(v["cached"] and v["status"] == "PASS" for v in cached.values()), str({k: (v["status"], v["cached"]) for k, v in cached.items()}))
    orig = (root / "b.gd").read_text(encoding="utf-8")
    # B1：簽名變更（Godot 會在呼叫端報錯）
    put(root, "b.gd", orig.replace("func val() -> int:", "func val(x: int) -> int:"))
    r = chk(mod, root, ["a.gd", "c.gd"])
    ok("B", "改了 a.gd／c.gd 依賴的 b.gd → 兩者都不使用過時的快取結果", not r["a.gd"]["cached"] and not r["c.gd"]["cached"], f"a.cached={r['a.gd']['cached']} c.cached={r['c.gd']['cached']}")
    ok("B", "b.gd 的 val() 多了參數 → 重查 a.gd（preload 相依）得 FAIL", r["a.gd"]["status"] == "FAIL", f"{r['a.gd']['status']} {' '.join(r['a.gd'].get('lines', []))[:90]}")
    ok("B", "b.gd 的 val() 多了參數 → 重查 c.gd（class_name 型別相依）得 FAIL", r["c.gd"]["status"] == "FAIL", f"{r['c.gd']['status']} {' '.join(r['c.gd'].get('lines', []))[:90]}")
    put(root, "b.gd", orig)
    # B2：回傳型別變更
    put(root, "b.gd", orig.replace("-> int:\n\treturn 1", "-> String:\n\treturn \"x\""))
    r = chk(mod, root, ["a.gd", "c.gd"])
    ok("B", "b.gd 的 val() 回傳型別改成 String → a.gd／c.gd 都 FAIL", r["a.gd"]["status"] == "FAIL" and r["c.gd"]["status"] == "FAIL", f"a={r['a.gd']['status']} c={r['c.gd']['status']}")
    put(root, "b.gd", orig)
    # B3：相依腳本本身語法錯誤
    put(root, "b.gd", orig.replace("return 1", "return ("))
    r = chk(mod, root, ["a.gd", "c.gd"])
    ok("B", "b.gd 語法錯誤 → 依賴它的 a.gd／c.gd 都 FAIL", r["a.gd"]["status"] == "FAIL" and r["c.gd"]["status"] == "FAIL", f"a={r['a.gd']['status']} c={r['c.gd']['status']}")
    put(root, "b.gd", orig)
    # B4：已知限制（Godot 行為，不是工具缺陷）：移除方法只是 UNSAFE 警告
    put(root, "b.gd", orig.replace("func val()", "func other()"))
    r = chk(mod, root, ["a.gd", "c.gd"])
    ok("B", "［已知限制，記錄現況］移除 b.gd 的 val() → Godot 預設不報錯，重查相依也是 PASS（所以覆蓋範圍文字必須明講）",
       r["a.gd"]["status"] == "PASS" and r["c.gd"]["status"] == "PASS", f"a={r['a.gd']['status']} c={r['c.gd']['status']}")
    put(root, "b.gd", orig)
    if hasattr(mod, "gd_deps"):
        idx = mod.gd_deps.DepIndex(root)
        d = idx.dependents({"res://b.gd"})
        ok("B", "反向依賴索引：b.gd 的直接相依 = a.gd（preload 路徑）＋c.gd（class_name）", set(d) == {"res://a.gd", "res://c.gd"}, str(sorted(d)))
        dd = idx.dependents({"res://data.res"})
        ok("B", "反向依賴索引：data.res 的直接相依 = preload 它的 a2.gd；只用 load() 的 a5.gd 不算（--check-only 不會因它失敗）", set(dd) == {"res://a2.gd"}, str(sorted(dd)))
        ok("B", "反向依賴索引：svc.gd（autoload）的直接相依 = 使用 Svc 的 a.gd", set(idx.dependents({"res://svc.gd"})) == {"res://a.gd"}, str(sorted(idx.dependents({"res://svc.gd"}))))
    else:
        na("B", "反向依賴索引")


def group_C(mod, root):
    chk(mod, root, ["a.gd"])
    ok("C", "前置：a.gd 快取 PASS", chk(mod, root, ["a.gd"])["a.gd"]["cached"])
    orig = (root / "svc.gd").read_text(encoding="utf-8")
    put(root, "svc.gd", orig.replace("func ping()", "func ping(x: int)"))     # autoload 簽名變更
    r = chk(mod, root, ["a.gd"])["a.gd"]
    ok("C", "改 autoload 腳本 svc.gd → a.gd 不用快取、重查", not r["cached"], f"cached={r['cached']}")
    ok("C", "autoload 的 ping() 多了參數 → a.gd 被判 FAIL（經第二意見載入）", r["status"] == "FAIL", f"{r['status']} {' '.join(r.get('lines', []))[:100]}")
    put(root, "svc.gd", orig)
    ok("C", "改回 → PASS", chk(mod, root, ["a.gd"])["a.gd"]["status"] == "PASS")
    put(root, "svc.gd", orig.replace("return 1", "return ("))                  # autoload 本身語法錯誤
    r = chk(mod, root, ["a.gd"])["a.gd"]
    ok("C", "autoload 腳本本身語法錯誤 → 依賴它的 a.gd 不得回報 PASS（實測舊版載入器會假通過）", r["status"] == "FAIL", f"{r['status']} {' '.join(r.get('lines', []))[:100]}")
    put(root, "svc.gd", orig)
    put(root, "svc.gd", orig.replace("func ping()", "func pong()"))
    r = chk(mod, root, ["a.gd"])["a.gd"]
    ok("C", "［已知限制，記錄現況］autoload 移除 ping() → Godot 預設不報錯（UNSAFE 警告）", r["status"] == "PASS", f"{r['status']}")
    put(root, "svc.gd", orig)


def group_K(mod, root):
    """class_name 快取（.godot/global_script_class_cache.cfg）與原始碼不一致。"""
    godot = (mod.resolve_godot() if hasattr(mod, "resolve_godot") else {"path": mod.find_godot()})["path"]

    def reimport():
        subprocess.run([godot, "--headless", "--path", str(root), "--import"], capture_output=True, timeout=180)

    ok("K", "前置：class 快取新鮮 → c.gd PASS", chk(mod, root, ["c.gd"], cache=False)["c.gd"]["status"] == "PASS")
    orig = (root / "b.gd").read_text(encoding="utf-8")
    put(root, "b.gd", orig.replace("class_name BHelper", "class_name BHelper2"))   # 改名，但快取還沒更新
    r = chk(mod, root, ["c.gd"], cache=False)["c.gd"]
    ok("K", "b.gd 的 class_name 改名、快取未更新 → c.gd（仍用 BHelper）不得 PASS（STALE）", r["status"] == "STALE", f"{r['status']} {' '.join(r.get('lines', []))[:100]}")
    reimport()
    r = chk(mod, root, ["c.gd"], cache=False)["c.gd"]
    ok("K", "重新 --import 後 → c.gd 正確 FAIL（找不到型別 BHelper）", r["status"] == "FAIL", f"{r['status']} {' '.join(r.get('lines', []))[:100]}")
    put(root, "b.gd", orig)
    reimport()
    ok("K", "改回並 --import → c.gd PASS", chk(mod, root, ["c.gd"], cache=False)["c.gd"]["status"] == "PASS")
    # 快取檔不存在
    cc = root / ".godot" / "global_script_class_cache.cfg"
    bak = cc.with_suffix(".bak")
    shutil.move(cc, bak)
    r = chk(mod, root, ["c.gd"], cache=False)["c.gd"]
    ok("K", "class 快取檔不存在 → c.gd FAIL 且註明可能是誤報、要先 --import", r["status"] == "FAIL" and "快取檔不存在" in r.get("note", ""), f"{r['status']} note={r.get('note', '')[:80]}")
    shutil.move(bak, cc)
    # 快取鍵含 class 快取指紋：快取 PASS 之後，快取檔改變 → 不重用
    chk(mod, root, ["c.gd"])
    ok("K", "前置：c.gd 快取 PASS", chk(mod, root, ["c.gd"])["c.gd"]["cached"])
    cc.write_bytes(cc.read_bytes() + b"\n")        # 內容變一個位元組（指紋改變）
    r = chk(mod, root, ["c.gd"])["c.gd"]
    ok("K", "class 快取檔變動 → c.gd 不重用舊的 PASS 快取", not r["cached"], f"cached={r['cached']}")
    reimport()


def group_D(mod, root):
    chk(mod, root, ["a.gd"])
    ok("D", "前置：a.gd 快取 PASS", chk(mod, root, ["a.gd"])["a.gd"]["cached"])
    orig = (root / "project.godot").read_text(encoding="utf-8")
    put(root, "project.godot", orig.replace('Svc="*res://svc.gd"\n', ""))   # 移除 autoload 註冊
    r = chk(mod, root, ["a.gd"])["a.gd"]
    ok("D", "project.godot 移除 autoload → 快取失效（不忽略設定變更）", not r["cached"], f"cached={r['cached']}")
    ok("D", "Svc 不再是 autoload → a.gd 判 FAIL（Identifier not found: Svc 是真錯誤）", r["status"] == "FAIL", f"{r['status']} {' '.join(r.get('lines', []))[:90]}")
    put(root, "project.godot", orig)
    r2 = chk(mod, root, ["a.gd"])["a.gd"]
    ok("D", "還原 project.godot → PASS，且不是舊 FAIL", r2["status"] == "PASS", f"{r2['status']} cached={r2['cached']}")
    put(root, "project.godot", orig.replace('config/name="gd_check_test"', 'config/name="gd_check_test2"'))
    r3 = chk(mod, root, ["a.gd"])["a.gd"]
    ok("D", "project.godot 只改無關設定（專案名）→ 仍保守地重查（不使用快取）", not r3["cached"], f"cached={r3['cached']}")
    put(root, "project.godot", orig)


def group_E(mod, root):
    for f in ("a2.gd", "a3.gd", "a4.gd"):
        chk(mod, root, [f])
    pre = chk(mod, root, ["a2.gd", "a3.gd", "a4.gd"])
    ok("E", "前置：三支腳本（preload .res／.tscn／.tres）都快取 PASS", all(v["status"] == "PASS" and v["cached"] for v in pre.values()), str({k: (v["status"], v["cached"]) for k, v in pre.items()}))
    # E1 刪除 .res（.res 不是舊版簽章涵蓋的副檔名）
    shutil.move(root / "data.res", root / "data.res.bak")
    r = chk(mod, root, ["a2.gd"])["a2.gd"]
    ok("E", ".res 被刪 → preload 它的 a2.gd 不得回報快取 PASS", r["status"] == "FAIL" and not r["cached"], f"{r['status']} cached={r['cached']} {' '.join(r.get('lines', []))[:80]}")
    shutil.move(root / "data.res.bak", root / "data.res")
    ok("E", ".res 還原 → a2.gd 回 PASS", chk(mod, root, ["a2.gd"])["a2.gd"]["status"] == "PASS")
    # E2 .res 內容被換（保持同名；換成不同大小的資源）
    pre2 = chk(mod, root, ["a2.gd"])["a2.gd"]
    data = (root / "data.res").read_bytes()
    (root / "data.res").write_bytes(data + b"\x00\x00")    # 改大小
    r = chk(mod, root, ["a2.gd"])["a2.gd"]
    ok("E", ".res 內容被改（大小變）→ 不使用快取", not r["cached"], f"cached={r['cached']} status={r['status']}")
    (root / "data.res").write_bytes(data)
    # E3 刪 .tscn
    shutil.move(root / "s.tscn", root / "s.tscn.bak")
    r = chk(mod, root, ["a3.gd"])["a3.gd"]
    ok("E", ".tscn 被刪 → a3.gd FAIL 且不用快取", r["status"] == "FAIL" and not r["cached"], f"{r['status']} cached={r['cached']}")
    shutil.move(root / "s.tscn.bak", root / "s.tscn")
    # E4 .tres 被改壞
    t = (root / "t.tres").read_text(encoding="utf-8")
    put(root, "t.tres", "[gd_resource type=\"Resource\" format=3\n\n[resource\n")
    r = chk(mod, root, ["a4.gd"])["a4.gd"]
    ok("E", ".tres 被改壞 → a4.gd 不用快取（結果取決於 preload 是否解析資源）", not r["cached"], f"{r['status']} cached={r['cached']} {' '.join(r.get('lines', []))[:80]}")
    put(root, "t.tres", t)
    # E5 新增資源：先刪除再新增同名 → 簽章變
    r = chk(mod, root, ["a2.gd", "a3.gd", "a4.gd"])
    ok("E", "全部還原後 → 三支都回 PASS", all(v["status"] == "PASS" for v in r.values()), str({k: v["status"] for k, v in r.items()}))


def group_F(mod, root):
    # F1：被檢查的檔案本身在檢查期間被改
    base = (root / "a.gd").read_text(encoding="utf-8")
    undo = hooked(mod, "a.gd", lambda: put(root, "a.gd", base + "# 另一個 Session 改的\n"))
    try:
        r = chk(mod, root, ["a.gd"])["a.gd"]
    finally:
        undo()
    ok("F", "檢查 a.gd 期間 a.gd 被改 → 不得回報 PASS（STALE）", r["status"] == "STALE", f"{r['status']} cached={r['cached']}")
    put(root, "a.gd", base)
    # F2：相依檔在檢查期間被改
    bb = (root / "b.gd").read_text(encoding="utf-8")
    undo = hooked(mod, "a.gd", lambda: put(root, "b.gd", bb + "# touched\n"))
    try:
        r = chk(mod, root, ["a.gd"])["a.gd"]
    finally:
        undo()
    ok("F", "檢查 a.gd 期間它依賴的 b.gd 被改 → PASS 不可信（STALE）", r["status"] == "STALE", f"{r['status']}")
    put(root, "b.gd", bb)
    # F3：無關檔案被改 → a.gd 仍可信，但不寫快取
    zz = (root / "z.gd").read_text(encoding="utf-8")
    if hasattr(mod, "run_checks_ex"):
        undo = hooked(mod, "a.gd", lambda: put(root, "z.gd", zz + "# touched\n"))
        try:
            res, meta = mod.run_checks_ex([root / "a.gd"], 1, 60, True)
        finally:
            undo()
        ok("F", "檢查期間只有無關的 z.gd 被改 → a.gd 仍 PASS，但本次不寫快取", res[0]["status"] == "PASS" and meta["cache_written"] == 0 and "z.gd" in meta["drift"], f"{res[0]['status']} written={meta['cache_written']} drift={meta['drift']}")
    else:
        na("F", "無關檔案被改時不寫快取")
    put(root, "z.gd", zz)
    # F4：project.godot 在檢查期間被改
    pg = (root / "project.godot").read_text(encoding="utf-8")
    undo = hooked(mod, "a.gd", lambda: put(root, "project.godot", pg + "\n"))
    try:
        r = chk(mod, root, ["a.gd"])["a.gd"]
    finally:
        undo()
    ok("F", "檢查期間 project.godot 被改 → PASS 不可信（STALE）", r["status"] == "STALE", f"{r['status']}")
    put(root, "project.godot", pg)


def group_G(mod, root):
    put(root, "bad.gd", f"extends Node\nfunc f():\n{TAB}print(oops\n")
    r1 = chk(mod, root, ["bad.gd"])["bad.gd"]
    r2 = chk(mod, root, ["bad.gd"])["bad.gd"]
    ok("G", "FAIL 結果不快取（每次重跑，不讓過期失敗擋路）", r1["status"] == "FAIL" and r2["status"] == "FAIL" and not r2["cached"], f"第二次 cached={r2['cached']}")
    to = mod.run_checks([root / "a.gd"], 1, 0.01, True)[0]
    r3 = chk(mod, root, ["a.gd"])["a.gd"]
    ok("G", "逾時 ERROR 不快取（下一次正常重跑得 PASS）", to["status"] == "ERROR" and r3["status"] == "PASS" and not r3["cached"], f"timeout={to['status']} next={r3['status']} cached={r3['cached']}")
    r4 = chk(mod, root, ["a.gd"])["a.gd"]
    ok("G", "PASS 結果會快取", r4["status"] == "PASS" and r4["cached"])
    put(root, "bad.gd", f"extends Node\nfunc f():\n{TAB}pass\n")
    r5 = chk(mod, root, ["bad.gd"])["bad.gd"]
    ok("G", "bad.gd 修好後 → PASS（舊 FAIL 不殘留）", r5["status"] == "PASS", f"{r5['status']} cached={r5['cached']}")
    if hasattr(mod, "run_checks_ex"):
        g = dict(mod.resolve_godot())
        g["version"] = g["version"] + ".SIMULATED"
        res, meta = mod.run_checks_ex([root / "a.gd"], 1, 60, True, godot_info=g)
        ok("G", "Godot 版本字串不同 → 不使用別版本的快取", not res[0]["cached"], f"cached={res[0]['cached']}")
    else:
        na("G", "Godot 版本納入快取鍵")
    (root / "bad.gd").unlink()


def group_V(mod, root):
    if not hasattr(mod, "resolve_godot"):
        na("V", "Godot 版本鎖定")
        return
    g = mod.resolve_godot()
    ok("V", "解析到 4.7.2 並記錄路徑與版本", g["ok"] and g["version"].startswith("4.7.2") and bool(g["path"]), f"{g['path']} {g['version']} 來源={g['source']}")
    saved = os.environ.get("GODOT_BIN")
    fake = root.parent / "fake_godot48.cmd"
    fake.write_text("@echo off\r\necho 4.8.0.stable.official.deadbeef1\r\n", encoding="ascii")
    try:
        os.environ["GODOT_BIN"] = str(fake)
        r = mod.run_checks([root / "a.gd"], 1, 30, False)[0]
        ok("V", "GODOT_BIN=4.8.0 → 檢查被拒絕（ERROR，不跑檢查、不退回 4.7.2）", r["status"] == "ERROR" and "4.8.0" in " ".join(r["lines"]), " ".join(r["lines"])[:120])
    finally:
        if saved is None:
            os.environ.pop("GODOT_BIN", None)
        else:
            os.environ["GODOT_BIN"] = saved


def git(repo: Path, *a: str) -> str:
    r = subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", *a], cwd=repo, capture_output=True, text=True, encoding="utf-8")
    return r.stdout


def group_H(mod, tmp: Path):
    if not hasattr(mod, "build_plan"):
        na("H", "變動偵測與反向依賴（build_plan）")
        return
    repo = tmp / "repo"
    proj = repo / "godot"
    build_project(mod, proj)
    (repo / ".gitignore").write_text(".godot/\n", encoding="utf-8")
    git(repo, "init", "-q")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "base")
    saved_bin = os.environ.get("GODOT_BIN")
    os.environ["GODOT_BIN"] = mod.resolve_godot()["path"]      # 暫存 repo 在別的磁碟：依 REPO 磁碟推算的路徑會失效，測試中明確指定
    try:
        _group_H_body(mod, repo, proj)
    finally:
        if saved_bin is None:
            os.environ.pop("GODOT_BIN", None)
        else:
            os.environ["GODOT_BIN"] = saved_bin


def _group_H_body(mod, repo: Path, proj: Path):
    bind(mod, proj, repo)

    def plan(**kw):
        return mod.build_plan([], False, kw.get("deps", "auto"), kw.get("depth", 1), kw.get("limit", 200))

    def names(p):
        return sorted(Path(t).name for t in p["targets"])

    p = plan()
    ok("H", "沒有變動 → 沒有目標", p["targets"] == [], str(names(p)))
    b = (proj / "b.gd").read_text(encoding="utf-8")
    put(proj, "b.gd", b + "# edit\n")
    p = plan()
    ok("H", "只改 b.gd → 目標＝b.gd＋直接相依 a.gd、c.gd", names(p) == ["a.gd", "b.gd", "c.gd"], str(names(p)))
    cov = mod.coverage_text(p)
    ok("H", "覆蓋範圍文字列出『直接相依』與未涵蓋的情況", "直接相依" in cov and "未涵蓋" in cov and "--all" in cov, cov[:120])
    ok("H", "--no-dependents → 只有 b.gd", names(plan(deps="off")) == ["b.gd"], str(names(plan(deps="off"))))
    git(repo, "checkout", "--", "godot/b.gd")
    # 刪除 b.gd（class_name BHelper 與路徑都消失；相依者要被找出來）
    (proj / "b.gd").unlink()
    p = plan()
    ok("H", "刪除 b.gd → 目標含 a.gd、c.gd（以 HEAD 版本回推被刪檔的 class_name）", names(p) == ["a.gd", "c.gd"], str(names(p)))
    res = chk(mod, proj, [Path(t).name for t in p["targets"]], cache=False)
    ok("H", "刪除 b.gd 後，a.gd、c.gd 實際檢查都 FAIL", all(v["status"] == "FAIL" for v in res.values()) and len(res) == 2, str({k: (v["status"], " ".join(v.get("lines", []))[:60]) for k, v in res.items()}))
    git(repo, "checkout", "--", "godot/b.gd")
    # 刪除 .res
    (proj / "data.res").unlink()
    p = plan()
    ok("H", "刪除 data.res（非 .gd）→ 目標含 preload 它的 a2.gd", names(p) == ["a2.gd"], str(names(p)))
    r2 = chk(mod, proj, ["a2.gd"], cache=False)["a2.gd"]
    ok("H", "…且實際檢查 a2.gd → FAIL", r2["status"] == "FAIL", f"{r2['status']} {' '.join(r2.get('lines', []))[:100]}")
    git(repo, "checkout", "--", "godot/data.res")
    # 新增 .res（未追蹤）
    shutil.copy(proj / "data.res", proj / "data2.res")
    p = plan()
    ok("H", "新增未追蹤的 data2.res（沒人引用）→ 不產生目標", p["targets"] == [], str(names(p)))
    (proj / "data2.res").unlink()
    # project.godot：autoload 移除
    pg = (proj / "project.godot").read_text(encoding="utf-8")
    put(proj, "project.godot", pg.replace('Svc="*res://svc.gd"\n', ""))
    p = plan()
    ok("H", "project.godot 移除 autoload Svc → 目標含 svc.gd 與使用 Svc 的 a.gd", {"a.gd", "svc.gd"} <= set(names(p)), str(names(p)))
    git(repo, "checkout", "--", "godot/project.godot")
    # project.godot：無關設定
    put(proj, "project.godot", pg.replace('config/name="gd_check_test"', 'config/name="renamed"'))
    p = plan()
    ok("H", "project.godot 只改專案名 → 不擴大檢查，並註明原因", p["targets"] == [] and any("不影響腳本編譯" in n for n in p["notes"]), str(p["notes"]))
    git(repo, "checkout", "--", "godot/project.godot")
    # project.godot：gdscript 警告設定 → 升級全專案
    put(proj, "project.godot", pg + "\n[debug]\n\ngdscript/warnings/unused_variable=2\n")
    p = plan()
    ok("H", "project.godot 的 gdscript 警告設定變動 → 升級成全專案", p["mode"] == "changed→all" and len(p["targets"]) >= 8, f"mode={p['mode']} n={len(p['targets'])}")
    git(repo, "checkout", "--", "godot/project.godot")
    # project.godot：只改外掛啟用清單 → 不升級、不擴大
    put(proj, "project.godot", pg + "\n[editor_plugins]\n\nenabled=PackedStringArray(\"res://addons/x/plugin.cfg\")\n")
    p = plan()
    ok("H", "project.godot 只改外掛啟用清單 → 不升級成全專案，註明只影響編輯器", p["mode"] == "changed" and p["targets"] == [] and any("外掛啟用清單" in n for n in p["notes"]), f"mode={p['mode']} {p['notes']}")
    git(repo, "checkout", "--", "godot/project.godot")
    # 上限
    put(proj, "b.gd", b + "# edit\n")
    p = plan(limit=1)
    ok("H", "相依數量超過上限 → 標示覆蓋不完整，exit code 2，且回報未檢查數量", p["incomplete"] and p["unchecked_dependents"] == 1 and mod.exit_code([{"status": "PASS"}], p) == 2, f"incomplete={p['incomplete']} unchecked={p['unchecked_dependents']}")
    git(repo, "checkout", "--", "godot/b.gd")
    # 指定檔案：預設不含相依，--dependents 才含
    p0 = mod.build_plan([str(proj / "b.gd")], False, "auto", 1, 200)
    p1 = mod.build_plan([str(proj / "b.gd")], False, "on", 1, 200)
    ok("H", "指定 b.gd：預設只查它並註明『未檢查相依』；--dependents 才納入 a.gd、c.gd",
       names(p0) == ["b.gd"] and "未檢查相依" in mod.coverage_text(p0) and names(p1) == ["a.gd", "b.gd", "c.gd"], f"{names(p0)} / {names(p1)}")
    # 深度 2：c.gd 依賴 b.gd；新增 d.gd 依賴 a.gd（const A = preload）
    put(proj, "d.gd", f"extends Node\nconst A = preload(\"res://a.gd\")\nfunc f():\n{TAB}return A\n")
    p1 = mod.build_plan([str(proj / "b.gd")], False, "on", 1, 200)
    p2 = mod.build_plan([str(proj / "b.gd")], False, "on", 2, 200)
    ok("H", "深度 1 不含 d.gd；深度 2 才含（間接相依需明確開啟）", "d.gd" not in names(p1) and "d.gd" in names(p2), f"{names(p1)} / {names(p2)}")
    (proj / "d.gd").unlink()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--module", default=str(HERE / "gd_check.py"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    mod = load_module(Path(a.module))
    only = {x.strip().upper() for x in a.only.split(",") if x.strip()}
    want = lambda g: not only or g in only  # noqa: E731
    print(f"被測模組：{a.module}")
    t0 = time.time()
    with tempfile.TemporaryDirectory(prefix="gdchk_test_") as td:
        tmp = Path(td)
        proj = tmp / "proj"
        build_project(mod, proj)
        bind(mod, proj)
        for g, fn in (("A", group_A), ("B", group_B), ("C", group_C), ("D", group_D), ("E", group_E), ("F", group_F), ("G", group_G), ("K", group_K), ("V", group_V)):
            if want(g):
                fn(mod, proj)
        if want("H"):
            group_H(mod, tmp)
    bad = [r for r in RESULTS if not r[1]]
    print(f"\n合計 {len(RESULTS)} 項：符合預期 {len(RESULTS) - len(bad)}／不符 {len(bad)}／此版本無此功能 {len(NA)}　耗時 {time.time() - t0:.0f}s")
    for _, _, line in bad:
        print("  不符：" + line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
