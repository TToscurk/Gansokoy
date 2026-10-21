#!/usr/bin/env python
"""gd_check — 改完 .gd 之後的快速檢查（約 0.2–0.5 秒／檔，不啟動完整遊戲）。

做什麼
  1. 對每支腳本跑 `godot --headless --path godot --check-only --script res://X.gd`（語法＋型別分析）。
  2. 只有 autoload 單例造成的誤報（`Identifier not found: StoryFlags/Wind/…`，因為 --check-only
     在 autoload 註冊之前就結束）才用 tools/dev/gd_load_check.gd 做第二意見（autoload 已註冊的真實編譯條件）。
  3. 不能只看 exit code：實測 exit 0 但輸出含 SCRIPT ERROR 的案例存在（相依腳本編譯失敗不會讓主腳本失敗），
     所以同時掃輸出文字。

預設只檢查「相對 HEAD 有變動或新增」的 godot/ 下 .gd。檔案內容＋專案簽章不變且 15 分鐘內，直接用快取結果。

用法
    python tools/dev/gd_check.py                    # 改過的 .gd
    python tools/dev/gd_check.py godot/a.gd res://b.gd
    python tools/dev/gd_check.py --all              # 全專案（非 .gdignore）
    python tools/dev/gd_check.py --no-cache --json
    python tools/dev/gd_check.py --selftest

exit code：0 全部 PASS（或無檔可查）；1 有 FAIL；2 有 ERROR（逾時、找不到 godot、無法判定）且無 FAIL。
Godot 執行檔：環境變數 GODOT_BIN；否則 PATH 上的 godot；再否則與 repo 同磁碟根目錄 /Godot/ 下最新的 Godot_v4*_console。
本工具只擋語法／型別／preload 路徑錯誤，不取代場景載入與功能測試。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROJ = REPO / "godot"
LOADER = Path(__file__).resolve().parent / "gd_load_check.gd"
CACHE_FILE = PROJ / ".godot" / "gd_check_cache.json"
CACHE_TTL = 15 * 60
SIG_EXT = (".gd", ".tscn", ".tres", ".gdshader")

RE_SCRIPT_ERR = re.compile(r"SCRIPT ERROR:[^\r\n]*")
RE_ERR_LINE = re.compile(r"(?m)^ERROR:[^\r\n]*")
RE_IDENT = re.compile(r"Identifier not found: (\w+)")


def find_godot() -> str | None:
    """依序找：環境變數 GODOT_BIN → PATH 上的 godot → 與 repo 同磁碟根目錄 /Godot/ 下最新的 Godot_v4*_console 執行檔（專案慣例位置）。"""
    cands = [os.environ.get("GODOT_BIN"), shutil.which("godot"), shutil.which("godot4")]
    cands += sorted(str(p) for p in Path(REPO.anchor, "Godot").glob("Godot_v4*_console.exe"))[-1:]
    return next((c for c in cands if c and os.path.exists(c)), None)


def autoload_names() -> set[str]:
    try:
        text = (PROJ / "project.godot").read_text(encoding="utf-8")
    except OSError:
        return set()
    m = re.search(r"(?ms)^\[autoload\]\s*$(.*?)(?=^\[|\Z)", text)
    if not m:
        return set()
    return {ln.split("=", 1)[0].strip() for ln in m.group(1).splitlines() if "=" in ln and not ln.lstrip().startswith(";")}


def classify_output(out: str, autoloads: set[str]) -> dict:
    """把 godot 輸出分成：真錯誤 / autoload 單例誤報 / 其他。"""
    real: list[str] = []
    auto: list[str] = []
    for ln in RE_SCRIPT_ERR.findall(out):
        m = RE_IDENT.search(ln)
        if (m and m.group(1) in autoloads) or "Failed to compile depended scripts" in ln:
            auto.append(ln.strip())
        else:
            real.append(ln.strip())
    for ln in RE_ERR_LINE.findall(out):
        if re.search(r"Can't load script|File not found|Failed loading resource|Parse error", ln):
            real.append(ln.strip())
    return {"real": real, "autoload": auto}


def is_gdignored(p: Path) -> bool:
    d = p.parent
    while True:
        if (d / ".gdignore").exists():
            return True
        if d == PROJ or d == d.parent:
            return False
        d = d.parent


def to_target(p: Path) -> tuple[str, bool]:
    """回傳 (傳給 godot 的路徑, 是否在專案內)。"""
    try:
        rel = p.resolve().relative_to(PROJ.resolve())
        return "res://" + rel.as_posix(), True
    except ValueError:
        return p.resolve().as_posix(), False


def git_lines(*args: str) -> list[str]:
    r = subprocess.run(["git", *args], cwd=REPO, capture_output=True)
    return [x.decode("utf-8") for x in r.stdout.split(b"\0") if x]


def changed_files() -> list[Path]:
    names = set(git_lines("diff", "--name-only", "-z", "HEAD", "--", "godot"))
    names |= set(git_lines("ls-files", "--others", "--exclude-standard", "-z", "--", "godot"))
    return sorted(REPO / n for n in names if n.endswith(".gd") and (REPO / n).is_file())


def all_files() -> list[Path]:
    out = []
    for root, dirs, fs in os.walk(PROJ):
        dirs[:] = [d for d in dirs if d != ".godot"]
        if ".gdignore" in fs:
            dirs[:] = []
            continue
        out += [Path(root) / f for f in fs if f.endswith(".gd")]
    return sorted(out)


def resolve_arg(a: str) -> Path:
    if a.startswith("res://"):
        return PROJ / a[6:]
    p = Path(a)
    if p.is_absolute():
        return p
    for base in (Path.cwd(), REPO, PROJ):
        if (base / p).exists():
            return (base / p).resolve()
    return (REPO / p).resolve()


def project_signature() -> str:
    h = hashlib.sha256()
    for root, dirs, fs in os.walk(PROJ):
        dirs[:] = sorted(d for d in dirs if d != ".godot")
        if ".gdignore" in fs:
            dirs[:] = []
            continue
        for f in sorted(fs):
            if f.endswith(SIG_EXT) or f == "project.godot":
                try:
                    st = os.stat(os.path.join(root, f))
                except OSError:
                    continue
                h.update(f"{root}/{f}|{st.st_size}|{st.st_mtime_ns}\n".encode("utf-8", "replace"))
    return h.hexdigest()[:16]


def load_cache() -> dict:
    try:
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_cache(c: dict) -> None:
    try:
        now = time.time()
        c = {k: v for k, v in c.items() if now - v.get("ts", 0) < CACHE_TTL}
        if len(c) > 5000:
            c = dict(sorted(c.items(), key=lambda kv: -kv[1]["ts"])[:5000])
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        tmp = CACHE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(c, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, CACHE_FILE)
    except OSError:
        pass


def run_godot(godot: str, args: list[str], timeout: float) -> tuple[int | None, str]:
    try:
        r = subprocess.run([godot, "--headless", "--path", str(PROJ), *args], capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "TIMEOUT"
    except OSError as e:
        return None, f"OSERROR {e}"
    return r.returncode, r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")


def check_one(godot: str, path: Path, autoloads: set[str], timeout: float) -> dict:
    target, inside = to_target(path)
    t = time.perf_counter()
    rc, out = run_godot(godot, ["--check-only", "--script", target], timeout)
    secs = round(time.perf_counter() - t, 2)
    res = {"path": target, "inside_project": inside, "secs": secs, "cached": False, "note": ""}
    if rc is None:
        res.update(status="ERROR", lines=[out[:200]])
        return res
    cl = classify_output(out, autoloads)
    if cl["real"]:
        res.update(status="FAIL", lines=(cl["real"] + cl["autoload"])[:8], note=f"exit={rc}")
    elif cl["autoload"]:
        res.update(status="NEEDS_SECOND", lines=cl["autoload"][:4], note=f"exit={rc}")
    elif rc == 0:
        res.update(status="PASS", lines=[])
    else:
        tail = [x for x in out.replace("\r", "").split("\n") if x.strip()][-4:]
        res.update(status="ERROR", lines=["exit=%d 但沒有可辨識的錯誤訊息（崩潰？）" % rc, *tail])
    return res


def second_opinion(godot: str, items: list[dict], timeout: float) -> None:
    if not items:
        return
    if not LOADER.exists():
        for it in items:
            it.update(status="ERROR", lines=["缺 tools/dev/gd_load_check.gd，無法做第二意見"])
        return
    targets = [it["path"] for it in items]
    rc, out = run_godot(godot, ["--script", LOADER.as_posix(), "--", *targets], timeout + 2 * len(targets))
    verdict: dict[str, str] = {}
    seg: dict[str, list[str]] = {}
    cur = None
    for ln in out.replace("\r", "").split("\n"):
        m = re.match(r"GDCHK\t(BEGIN|PASS|FAIL)\t(.+)$", ln)
        if m:
            if m.group(1) == "BEGIN":
                cur = m.group(2)
                seg[cur] = []
            else:
                verdict[m.group(2)] = m.group(1)
                cur = None
        elif cur and ("ERROR" in ln):
            seg[cur].append(ln.strip())
    for it in items:
        v = verdict.get(it["path"])
        if v == "PASS":
            it.update(status="PASS", note="autoload 單例已註冊條件下通過（--check-only 的誤報）", lines=[])
        elif v == "FAIL":
            it.update(status="FAIL", lines=(seg.get(it["path"]) or ["load() 後 can_instantiate()=false"])[:8], note="第二意見確認失敗")
        else:
            it.update(status="ERROR", lines=["第二意見沒有回報此檔（rc=%s）：%s" % (rc, out[-200:].replace("\n", " "))])


def run_checks(paths: list[Path], jobs: int, timeout: float, use_cache: bool) -> list[dict]:
    godot = find_godot()
    if not godot:
        return [{"path": p.as_posix(), "status": "ERROR", "lines": ["找不到 godot 執行檔（設環境變數 GODOT_BIN）"], "secs": 0, "cached": False, "note": ""} for p in paths] or []
    autoloads = autoload_names()
    results: list[dict] = []
    todo: list[tuple[Path, str]] = []
    cache = load_cache() if use_cache else {}
    sig = project_signature() if use_cache else ""
    ver = ""
    if use_cache:
        _, ver = run_godot(godot, ["--version"], 20)
        ver = ver.strip()[:40]
    now = time.time()
    for p in paths:
        target, inside = to_target(p)
        if not p.is_file():
            results.append({"path": target, "status": "ERROR", "lines": ["檔案不存在"], "secs": 0, "cached": False, "note": ""})
            continue
        if inside and is_gdignored(p):
            results.append({"path": target, "status": "SKIP", "lines": [], "secs": 0, "cached": False, "note": "在 .gdignore 目錄內，res:// 無法載入"})
            continue
        key = ""
        if use_cache:
            key = hashlib.sha256(p.read_bytes()).hexdigest()[:20] + "|" + target + "|" + ver + "|" + sig
            hit = cache.get(key)
            if hit and now - hit["ts"] < CACHE_TTL:
                results.append({**hit["res"], "path": target, "cached": True, "secs": 0})
                continue
        todo.append((p, key))
    fresh: list[dict] = []
    with ThreadPoolExecutor(max(1, min(jobs, len(todo) or 1))) as ex:
        fresh = list(ex.map(lambda pk: check_one(godot, pk[0], autoloads, timeout), todo))
    second_opinion(godot, [r for r in fresh if r["status"] == "NEEDS_SECOND"], timeout)
    for (p, key), r in zip(todo, fresh):
        if not r.get("inside_project", True):
            r["note"] = (r.get("note", "") + " 專案外檔案：autoload／class_name 解析可能與專案內不同").strip()
        if use_cache and key and r["status"] in ("PASS", "FAIL"):
            cache[key] = {"ts": now, "res": {k: v for k, v in r.items() if k not in ("cached", "secs")}}
        results.append(r)
    if use_cache and todo:
        save_cache(cache)
    return sorted(results, key=lambda r: r["path"])


def render(results: list[dict]) -> str:
    out = []
    for r in results:
        tag = r["status"]
        extra = " (快取)" if r.get("cached") else (f" {r['secs']}s" if r.get("secs") else "")
        note = f"  # {r['note']}" if r.get("note") else ""
        out.append(f"{tag:5s} {r['path']}{extra}{note}")
        for ln in r.get("lines", [])[:6]:
            out.append("      | " + ln[:200])
    c = {s: sum(1 for r in results if r["status"] == s) for s in ("PASS", "FAIL", "ERROR", "SKIP")}
    out.append(f"gd_check: {len(results)} 檔 — PASS {c['PASS']} / FAIL {c['FAIL']} / ERROR {c['ERROR']} / SKIP {c['SKIP']}")
    return "\n".join(out)


def exit_code(results: list[dict]) -> int:
    if any(r["status"] == "FAIL" for r in results):
        return 1
    if any(r["status"] == "ERROR" for r in results):
        return 2
    return 0


def _selftest() -> int:
    ok = True

    def case(name: str, cond: bool) -> None:
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name)
        ok = ok and cond

    # --- 純解析（不需 godot）---
    al = {"StoryFlags", "Wind"}
    c = classify_output('SCRIPT ERROR: Compile Error: Identifier not found: StoryFlags\r\nERROR: Failed to load script "res://x.gd" with error "Compilation failed".', al)
    case("autoload 誤報被分到 autoload、不算真錯誤", not c["real"] and len(c["autoload"]) == 1)
    c = classify_output("SCRIPT ERROR: Compile Error: Identifier not found: TypoName", al)
    case("非 autoload 的 Identifier not found 仍是真錯誤", len(c["real"]) == 1)
    c = classify_output("SCRIPT ERROR: Parse Error: x\nSCRIPT ERROR: Compile Error: Identifier not found: Wind", al)
    case("真錯誤與 autoload 誤報並存 → 真錯誤不被吞掉", len(c["real"]) == 1 and len(c["autoload"]) == 1)
    c = classify_output("ERROR: Attempt to open script 'a.gd' resulted in error 'File not found'.", al)
    case("File not found 視為真錯誤", len(c["real"]) == 1)
    c = classify_output("SCRIPT ERROR: Compile Error: Failed to compile depended scripts.\nSCRIPT ERROR: Compile Error: Identifier not found: Wind", al)
    case("'Failed to compile depended scripts' 連鎖訊息歸入待第二意見、不算真錯誤", not c["real"] and len(c["autoload"]) == 2)

    godot = find_godot()
    if not godot:
        print("FAIL 找不到 godot，無法做整合測試")
        return 1
    with tempfile.TemporaryDirectory() as td:
        def w(name: str, body: str) -> Path:
            p = Path(td) / name
            p.write_text(body, encoding="utf-8", newline="\n")
            return p
        good = w("good.gd", "extends Node\nfunc f(a: int) -> int:\n\treturn a + 1\n")
        bad_syn = w("bad_syntax.gd", "extends Node\nfunc f():\n\tprint(oops\n")
        bad_typ = w("bad_types.gd", "extends Node\nfunc f() -> int:\n\tvar s: String = 5\n\treturn \"x\"\n")
        r = {os.path.basename(x["path"]): x for x in run_checks([good, bad_syn, bad_typ], 3, 60, False)}
        case("正常腳本 → PASS", r["good.gd"]["status"] == "PASS")
        case("語法錯誤 → FAIL（不被誤判成功）", r["bad_syntax.gd"]["status"] == "FAIL")
        case("型別錯誤 → FAIL", r["bad_types.gd"]["status"] == "FAIL")
        missing = run_checks([Path(td) / "nope.gd"], 1, 30, False)
        case("檔案不存在 → ERROR（不是 PASS）", missing[0]["status"] == "ERROR")
        to = run_checks([good], 1, 0.01, False)
        case("逾時 → ERROR（不是 PASS）", to[0]["status"] == "ERROR")
        real_find = find_godot
        globals()["find_godot"] = lambda: None
        try:
            nb = run_checks([good], 1, 30, False)
        finally:
            globals()["find_godot"] = real_find
        case("找不到 godot → ERROR（exit 2，不是 PASS）", nb[0]["status"] == "ERROR" and exit_code(nb) == 2)
        case("exit_code：有 FAIL → 1", exit_code([{"status": "FAIL"}, {"status": "PASS"}]) == 1)
        case("exit_code：只有 ERROR → 2", exit_code([{"status": "ERROR"}, {"status": "PASS"}]) == 2)
        case("exit_code：全 PASS → 0", exit_code([{"status": "PASS"}]) == 0)
        # 快取：同檔第二次命中；改內容後失效（固定專案簽章，避免其他人同時改專案造成誤判）
        real_sig = project_signature
        globals()["project_signature"] = lambda: "selftest-fixed-signature"
        try:
            a = run_checks([good], 1, 60, True)
            b = run_checks([good], 1, 60, True)
            case("同一份未改動檔案第二次 → 用快取", (not a[0]["cached"]) and b[0]["cached"])
            good.write_text("extends Node\nfunc f(a: int) -> int:\n\treturn a + 2\n", encoding="utf-8", newline="\n")
            c2 = run_checks([good], 1, 60, True)
            case("改了內容 → 快取失效重查", not c2[0]["cached"])
            globals()["project_signature"] = lambda: "selftest-changed-signature"
            c3 = run_checks([good], 1, 60, True)
            case("專案簽章變了（相依檔案有動）→ 快取失效重查", not c3[0]["cached"])
        finally:
            globals()["project_signature"] = real_sig
    # 整合：已知引用 autoload 的專案腳本（--check-only 會誤報）
    main_gd = PROJ / "scripts" / "main.gd"
    if main_gd.exists():
        m = run_checks([main_gd], 1, 60, False)
        case("autoload 誤報案例 scripts/main.gd → 第二意見 PASS", m[0]["status"] == "PASS")
    print("selftest:", "ALL PASS" if ok else "FAILED")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="改完 .gd 的快速檢查（--check-only＋autoload 感知第二意見）")
    ap.add_argument("files", nargs="*")
    ap.add_argument("--all", action="store_true", help="全專案所有 .gd（略過 .gdignore）")
    ap.add_argument("--no-cache", action="store_true")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    paths = [resolve_arg(x) for x in a.files] if a.files else (all_files() if a.all else changed_files())
    if not paths:
        print("gd_check: 沒有需要檢查的 .gd（無相對 HEAD 的變動）")
        return 0
    results = run_checks(paths, a.jobs, a.timeout, not a.no_cache)
    print(json.dumps(results, ensure_ascii=False, indent=1) if a.json else render(results))
    return exit_code(results)


if __name__ == "__main__":
    sys.exit(main())
