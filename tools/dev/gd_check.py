#!/usr/bin/env python
"""gd_check — 改完 .gd 之後的快速檢查（約 0.2–0.5 秒／檔，不啟動完整遊戲）。

做什麼
  1. 對每支腳本跑 `godot --headless --path godot --check-only --script res://X.gd`（語法＋型別分析）。
  2. 只有 autoload 單例造成的誤報（`Identifier not found: StoryFlags/Wind/…`，因為 --check-only
     在 autoload 註冊之前就結束）才用 tools/dev/gd_load_check.gd 做第二意見（autoload 已註冊的真實編譯條件）。
  3. 不能只看 exit code：實測 exit 0 但輸出含 SCRIPT ERROR 的案例存在（相依腳本編譯失敗不會讓主腳本失敗），
     所以同時掃輸出文字。

預設檢查範圍（不帶檔名、不帶 --all）＝「相對 HEAD 有變動的 .gd」＋「它們的直接相依 .gd」
  相依來源（文字索引，見 gd_deps.py）：preload／extends 路徑（編譯期引用）、class_name、autoload 名稱；load() 不算；
  非 .gd 檔（.res/.tscn/.tres/貼圖…）變動或被刪除，也會找出 preload 它們的腳本；
  project.godot 的 [autoload] 變動（以名稱比對，含 uid:// 註冊）→ 相關腳本；gdscript 警告設定變動 → 升級成全專案；
  其他設定段（含外掛啟用清單）變動 → 不擴大，只在輸出註明。
  每次執行結尾會印「覆蓋範圍」：查了哪些、哪些情況沒有涵蓋。需要完整保證用 --all。

Godot 執行檔（版本鎖定，絕不自動換版）
  1. 環境變數 GODOT_BIN（有設就只用它；不存在或版本不符一律報錯，不會退回其他版本）。
  2. 否則 PATH 上的 godot／godot4，再來是 <repo 所在磁碟>/Godot/ 下檔名為 Godot_v<要求版本>-stable*_console 的檔案；
     只選「版本剛好符合」者，略過的候選會列在輸出裡。
  要求版本預設 4.7.2（GODOT_REQUIRED_VERSION 可覆寫）。找到的路徑與版本印在第一行並寫入 godot/.godot/gd_check_last_run.json。

快取策略
  - 只快取 PASS；FAIL／ERROR／STALE 每次都重跑（便宜、而且不會讓過期的失敗擋路）。
  - 快取鍵 = 檔案內容雜湊 ＋ Godot 完整版本 ＋ 全專案簽章（所有 .gd/.tscn/.tres/.gdshader/.res/.scn/.gdextension
    與 project.godot 的大小＋修改時間；任何一個變動，全部快取失效）＋ 該腳本內所有 res:// 字面路徑（任何副檔名）的存在／大小／時間。
  - 檢查期間若檔案被改（另一個 Session）：該檔 → STALE；相依檔被改 → 其 PASS 改標 STALE；本次不寫快取。
    STALE 與 ERROR 同等（exit 2），代表「請重跑」，不是通過。
  - class_name 清單來自 godot/.godot/global_script_class_cache.cfg（編輯器／--import 才會更新）。實測：class_name 改名而快取沒更新時，
    用到舊名稱的腳本仍會 --check-only 通過（假通過）。本工具比對快取與原始碼，不一致 → 用到該名稱的 PASS 改標 STALE；
    快取檔不存在 → 相關 FAIL 加註「可能是誤報」。快取指紋也在快取鍵裡。本工具不會自動跑 --import（會寫專案快取、編輯器開著時有衝突）。

Godot 本身的限制（不是本工具能補的）
  - 相依腳本「移除／改名方法」預設只是 UNSAFE_METHOD_ACCESS 警告，--check-only 不報錯，重查相依腳本也一樣。
    （簽名、回傳型別、class_name、preload 路徑、autoload 註冊的變動才會被抓到；專案若把 unsafe_method_access 設成錯誤才會抓到移除。）

用法
    python tools/dev/gd_check.py                    # 改過的 .gd ＋ 直接相依
    python tools/dev/gd_check.py godot/a.gd res://b.gd       # 只查指定檔（加 --dependents 納入直接相依）
    python tools/dev/gd_check.py --all              # 全專案（非 .gdignore）
    python tools/dev/gd_check.py --plan             # 只印要查哪些與覆蓋範圍，不啟動 godot
    python tools/dev/gd_check.py --which-godot      # 只印選到的 godot 與版本
    python tools/dev/gd_check.py --no-cache --json
    python tools/dev/gd_check.py --selftest

exit code：0 全部 PASS（或無檔可查）；1 有 FAIL；2 有 ERROR／STALE／覆蓋不完整（無 FAIL 時）。
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gd_deps  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
LOADER = Path(__file__).resolve().parent / "gd_load_check.gd"
DEFAULT_REQUIRED_GODOT = "4.7.2"
CACHE_TTL = 15 * 60
SIG_EXT = (".gd", ".tscn", ".tres", ".gdshader", ".res", ".scn", ".gdextension")

PROJ = Path(os.environ.get("GD_CHECK_PROJECT") or (REPO / "godot")).resolve()
CACHE_FILE = PROJ / ".godot" / "gd_check_cache.json"
LAST_RUN_FILE = PROJ / ".godot" / "gd_check_last_run.json"


def set_project(path: str | os.PathLike) -> None:
    """切換目標專案（測試用／其他 Godot 專案）。"""
    global PROJ, CACHE_FILE, LAST_RUN_FILE
    PROJ = Path(path).resolve()
    CACHE_FILE = PROJ / ".godot" / "gd_check_cache.json"
    LAST_RUN_FILE = PROJ / ".godot" / "gd_check_last_run.json"


RE_SCRIPT_ERR = re.compile(r"SCRIPT ERROR:[^\r\n]*")
RE_ERR_LINE = re.compile(r"(?m)^ERROR:[^\r\n]*")
RE_IDENT = re.compile(r"Identifier not found: (\w+)")
RE_CACHE_ENTRY = re.compile(r'"class":\s*&"(\w+)"[^{}]*?"path":\s*"(res://[^"]+)"')   # 實檔是多行格式；[^{}] 保證不跨筆
RE_WORD = re.compile(r"[^\W\d]\w*")
RE_GODOT_VER = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?\.(stable|rc\d*|beta\d*|dev\d*|alpha\d*)(?:\.(\w+))?(?:\.([0-9a-f]{7,}))?\s*$")


# ───────────────────────── Godot 執行檔：鎖版本 ─────────────────────────

def required_godot() -> str:
    return os.environ.get("GODOT_REQUIRED_VERSION", "").strip() or DEFAULT_REQUIRED_GODOT


def parse_godot_version(s: str) -> dict | None:
    m = RE_GODOT_VER.match((s or "").strip())
    if not m:
        return None
    return {"major": int(m.group(1)), "minor": int(m.group(2)), "patch": int(m.group(3) or 0),
            "has_patch": m.group(3) is not None, "status": m.group(4), "raw": s.strip()}


def version_matches(found: str, required: str) -> tuple[bool, str]:
    """found＝`godot --version` 的輸出；required 形如 4.7.2（或只寫 4.7＝不比 patch）。只接受 stable。"""
    f = parse_godot_version(found)
    if not f:
        return False, f"無法解析版本字串 {found!r}"
    rp = [int(x) for x in required.split(".")[:3] if x.isdigit()]
    if len(rp) < 2:
        return False, f"要求版本 {required!r} 格式不對（應為 4.7.2）"
    if f["status"] != "stable":
        return False, f"是 {f['major']}.{f['minor']}.{f['patch']}.{f['status']}，不是 stable 版"
    got = [f["major"], f["minor"], f["patch"]][: len(rp)]
    if got != rp:
        return False, f"是 {f['major']}.{f['minor']}.{f['patch']}，專案要求 {required}"
    return True, ""


_VERSION_MEMO: dict[tuple, tuple[str | None, str]] = {}


def probe_godot(path: str) -> tuple[str | None, str]:
    """跑 `godot --version`；回傳 (版本字串 or None, 錯誤)。同一程序內以 (路徑,大小,mtime) 記憶。"""
    try:
        st = os.stat(path)
        memo_key = (path, st.st_size, st.st_mtime_ns)
    except OSError as e:
        return None, f"無法讀取 {path}：{e}"
    if memo_key in _VERSION_MEMO:
        return _VERSION_MEMO[memo_key]
    try:
        r = subprocess.run([path, "--version"], capture_output=True, timeout=20)
        out = (r.stdout.decode("utf-8", "replace") or r.stderr.decode("utf-8", "replace")).strip()
        line = next((x.strip() for x in out.splitlines() if x.strip()), "")
        res = (line, "") if line else (None, f"{path} --version 沒有輸出（exit={r.returncode}）")
    except subprocess.TimeoutExpired:
        res = (None, f"{path} --version 逾時")
    except OSError as e:
        res = (None, f"{path} 無法執行：{e}")
    _VERSION_MEMO[memo_key] = res
    return res


def project_feature_version() -> str | None:
    """project.godot 的 config/features 第一個 N.N（例如 4.7）。"""
    try:
        t = (PROJ / "project.godot").read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r'(?m)^config/features=PackedStringArray\("(\d+\.\d+)"', t)
    return m.group(1) if m else None


def resolve_godot() -> dict:
    """選 godot 執行檔並驗證版本。不修改 PATH／環境；GODOT_BIN 有設就不退回其他版本。"""
    req = required_godot()
    info = {"ok": False, "path": None, "version": None, "source": None, "required": req,
            "skipped": [], "error": "", "project_features": project_feature_version()}
    env = os.environ.get("GODOT_BIN", "").strip()
    cands: list[tuple[str, str]] = []
    if env:
        cands = [("GODOT_BIN", env)]
    else:
        for n in ("godot", "godot4"):
            w = shutil.which(n)
            if w:
                cands.append((f"PATH:{n}", w))
        d = Path(REPO.anchor) / "Godot"
        if d.is_dir():
            cands += [("pinned-dir", str(p)) for p in sorted(d.glob(f"Godot_v{req}-stable*_console*"))]
    if not cands:
        info["error"] = (f"找不到 Godot {req}：未設定 GODOT_BIN、PATH 上沒有 godot、"
                         f"{Path(REPO.anchor) / 'Godot'} 下沒有 Godot_v{req}-stable*_console。請設定環境變數 GODOT_BIN。")
        return info
    for source, path in cands:
        if not os.path.exists(path):
            if source == "GODOT_BIN":
                info["error"] = f"GODOT_BIN 指到不存在的檔案：{path}（不會自動改用其他 Godot）"
                return info
            continue
        ver, err = probe_godot(path)
        if ver is None:
            if source == "GODOT_BIN":
                info["error"] = f"GODOT_BIN={path} 無法取得版本：{err}（不會自動改用其他 Godot）"
                return info
            info["skipped"].append({"path": path, "source": source, "version": None, "why": err})
            continue
        ok, why = version_matches(ver, req)
        if ok:
            info.update(ok=True, path=path, version=ver, source=source)
            break
        if source == "GODOT_BIN":
            info.update(path=path, version=ver, source=source,
                        error=f"Godot 版本不符：GODOT_BIN={path} {why}（版本 {ver}）。不會自動改用其他 Godot；"
                              f"請改指到 {req}，或明確設 GODOT_REQUIRED_VERSION。")
            return info
        info["skipped"].append({"path": path, "source": source, "version": ver, "why": why})
    if not info["ok"]:
        sk = "；".join(f"{s['path']}（{s['version'] or '?'}：{s['why']}）" for s in info["skipped"]) or "無"
        info["error"] = f"找不到符合版本 {req} 的 Godot。略過的候選：{sk}。請設定 GODOT_BIN 指向 {req}。"
        return info
    feat = info["project_features"]
    if feat and req.split(".")[:2] != feat.split("."):
        info.update(ok=False, error=f"要求版本 {req} 與 project.godot 的 config/features={feat} 不一致；"
                                    f"請同步更新 GODOT_REQUIRED_VERSION／DEFAULT_REQUIRED_GODOT 或專案設定。")
    return info


def find_godot() -> str | None:
    g = resolve_godot()
    return g["path"] if g["ok"] else None


def godot_header(g: dict) -> str:
    if g["ok"]:
        extra = ("；略過 " + ", ".join(f"{s['path']}({s['version']})" for s in g["skipped"])) if g["skipped"] else ""
        return f"godot: {g['path']} | {g['version']} | 來源={g['source']} | 要求={g['required']} ✓{extra}"
    return f"godot: ✗ {g['error']}"


# ───────────────────────── 解析與基本工具 ─────────────────────────

def autoload_names() -> set[str]:
    try:
        return set(gd_deps.parse_autoloads((PROJ / "project.godot").read_text(encoding="utf-8")))
    except OSError:
        return set()


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


# ───────────────────────── git 變動 → 檢查種子 ─────────────────────────

def git_lines(*args: str) -> list[str]:
    r = subprocess.run(["git", *args], cwd=REPO, capture_output=True)
    return [x.decode("utf-8") for x in r.stdout.split(b"\0") if x]


def git_show_head(rel_repo_path: str) -> str | None:
    r = subprocess.run(["git", "show", f"HEAD:{rel_repo_path}"], cwd=REPO, capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def proj_rel() -> str | None:
    try:
        return PROJ.relative_to(REPO.resolve()).as_posix()
    except ValueError:
        return None


def changed_seeds() -> tuple[list[str], list[str]]:
    """相對 HEAD 變動（含未追蹤）的專案內檔案 → (仍存在的 res:// 路徑, 已刪除的 res:// 路徑)。不含 .godot/。"""
    rel = proj_rel()
    if rel is None:
        raise RuntimeError("專案不在 repo 內，無法用 git 判斷變動；請明確列出檔案或用 --all")
    names = set(git_lines("diff", "--name-only", "--no-renames", "-z", "HEAD", "--", rel))
    names |= set(git_lines("ls-files", "--others", "--exclude-standard", "-z", "--", rel))
    exist, gone = [], []
    for n in sorted(names):
        sub = n[len(rel) + 1:] if n.startswith(rel + "/") else n
        if sub.startswith(".godot/") or sub.endswith(".uid") or sub.endswith(".import"):
            continue
        res = "res://" + sub
        (exist if (REPO / n).is_file() else gone).append(res)
    return exist, gone


def _parse_ini(text: str) -> dict[str, dict[str, str]]:
    sec, last, out = "", None, {}
    for ln in text.splitlines():
        m = re.match(r"^\[([^\]]+)\]\s*$", ln)
        if m:
            sec, last = m.group(1), None
            out.setdefault(sec, {})
            continue
        m = re.match(r"^([A-Za-z0-9_/.\-]+)=(.*)$", ln)
        if m:
            last = m.group(1)
            out.setdefault(sec, {})[last] = m.group(2)
        elif last is not None and ln.strip():
            out[sec][last] += "\n" + ln
    return out


def project_godot_effects(head_text: str | None, now_text: str | None) -> dict:
    """比較 project.godot：autoload 變了哪些名稱／路徑；是否動到會影響編譯的設定（要升級成全專案）。"""
    eff = {"names": set(), "paths": set(), "escalate": False, "notes": []}
    if head_text is None or now_text is None or head_text == now_text:
        return eff
    a, b = _parse_ini(head_text), _parse_ini(now_text)
    changed_secs = []
    for sec in sorted(set(a) | set(b)):
        ka, kb = a.get(sec, {}), b.get(sec, {})
        for k in sorted(set(ka) | set(kb)):
            if ka.get(k) == kb.get(k):
                continue
            changed_secs.append(sec)
            if sec == "autoload":
                eff["names"].add(k)
                for v in (ka.get(k), kb.get(k)):
                    if v:
                        eff["paths"].add(v.strip().strip('"').lstrip("*"))
            elif sec == "gdscript" or k.startswith("gdscript/") or sec.startswith("gdscript"):
                eff["escalate"] = True
                eff["notes"].append(f"project.godot [{sec}] {k} 變動 → 可能影響編譯／警告，升級為全專案檢查")
            elif sec == "editor_plugins":
                eff["notes"].append("project.godot 外掛啟用清單變動：只影響編輯器載入哪些外掛，未擴大檢查（外掛若新增 autoload 會反映在 [autoload] 段）")
    others = sorted({s for s in changed_secs if s not in ("autoload", "editor_plugins", "gdscript")})
    if others and not eff["escalate"]:
        eff["notes"].append(f"project.godot 其他設定段變動（{', '.join(others)}）：判定不影響腳本編譯，未擴大檢查")
    return eff


def is_script_loadable(res: str) -> bool:
    return res.endswith(".gd") and (PROJ / res[6:]).is_file()


def build_plan(files: list[str], all_: bool, deps_mode: str, depth: int, limit: int) -> dict:
    """決定要檢查哪些檔，以及覆蓋範圍。deps_mode：auto｜on｜off。"""
    plan = {"mode": "", "targets": [], "dependents": {}, "seeds": 0, "notes": [], "incomplete": False,
            "unchecked_dependents": 0, "depth": depth}
    if all_:
        plan["mode"] = "all"
        plan["targets"] = all_files()
        return plan
    use_deps = deps_mode == "on" or (deps_mode == "auto" and not files)
    extra_names: set[str] = set()
    if files:
        plan["mode"] = "explicit"
        explicit = [resolve_arg(x) for x in files]
        seeds_res = {to_target(p)[0] for p in explicit if to_target(p)[1]}
        targets = list(explicit)
    else:
        plan["mode"] = "changed"
        exist_res, gone = changed_seeds()
        seeds_res = set(exist_res) | set(gone)
        targets = [PROJ / r[6:] for r in exist_res if r.endswith(".gd")]
        rel = proj_rel()
        if "res://project.godot" in seeds_res:
            head = git_show_head(f"{rel}/project.godot")
            try:
                now = (PROJ / "project.godot").read_text(encoding="utf-8")
            except OSError:
                now = None
            eff = project_godot_effects(head, now)
            plan["notes"] += eff["notes"]
            if eff["escalate"]:
                plan["mode"] = "changed→all"
                plan["targets"] = all_files()
                return plan
            extra_names |= eff["names"]
            for pth in eff["paths"]:
                seeds_res.add(pth)
                if pth.endswith(".gd") and (PROJ / pth[6:]).is_file():
                    targets.append(PROJ / pth[6:])
    plan["seeds"] = len(seeds_res)
    if use_deps:
        rel = proj_rel()
        reader = (lambda r: git_show_head(f"{rel}/{r[6:]}")) if rel else None
        idx = gd_deps.DepIndex(PROJ, head_reader=reader)
        deps = idx.dependents(seeds_res, depth=depth, extra_names=extra_names)
        have = {to_target(p)[0] for p in targets}
        add = {k: v for k, v in sorted(deps.items()) if k not in have and is_script_loadable(k)}
        if len(add) > limit:
            plan["incomplete"] = True
            plan["unchecked_dependents"] = len(add) - limit
            add = dict(list(add.items())[:limit])
        plan["dependents"] = add
        targets += [PROJ / k[6:] for k in add]
    plan["targets"] = sorted(set(targets))
    return plan


# ───────────────────────── 快取與簽章 ─────────────────────────

def project_snapshot() -> dict[str, tuple[int, int]]:
    snap: dict[str, tuple[int, int]] = {}
    for root, dirs, fs in os.walk(PROJ):
        dirs[:] = sorted(d for d in dirs if d != ".godot")
        if ".gdignore" in fs:
            dirs[:] = []
            continue
        for f in fs:
            if f.endswith(SIG_EXT) or f == "project.godot":
                fp = os.path.join(root, f)
                try:
                    st = os.stat(fp)
                except OSError:
                    continue
                snap[os.path.relpath(fp, PROJ).replace("\\", "/")] = (st.st_size, st.st_mtime_ns)
    return snap


def signature(snap: dict) -> str:
    h = hashlib.sha256()
    for k in sorted(snap):
        h.update(f"{k}|{snap[k][0]}|{snap[k][1]}\n".encode("utf-8", "replace"))
    return h.hexdigest()[:16]


def project_signature() -> str:
    return signature(project_snapshot())


def dep_fingerprint(text: str, target: str) -> str:
    """腳本內所有 res:// 字面路徑（任何副檔名）的 存在／大小／mtime；偵測 .res／貼圖被刪或換。"""
    parts = []
    for r in sorted(gd_deps.refs_of(text, target)):
        fp = PROJ / r[6:]
        try:
            st = os.stat(fp)
            parts.append(f"{r}|{st.st_size}|{st.st_mtime_ns}")
        except OSError:
            parts.append(f"{r}|missing")
    return hashlib.sha256("\n".join(parts).encode("utf-8", "replace")).hexdigest()[:12]


def class_cache_path() -> Path:
    return PROJ / ".godot" / "global_script_class_cache.cfg"


def class_cache_fingerprint() -> str:
    try:
        st = os.stat(class_cache_path())
        return f"{st.st_size}|{st.st_mtime_ns}"
    except OSError:
        return "missing"


def read_class_cache() -> dict[str, str] | None:
    """Godot 的全域 class_name 清單 {名稱: res 路徑}；檔案不存在回傳 None。"""
    try:
        text = class_cache_path().read_text(encoding="utf-8")
    except OSError:
        return None
    return {m.group(1): m.group(2) for m in RE_CACHE_ENTRY.finditer(text)}


def stale_class_names(texts: dict[str, str]) -> set[str]:
    """class_name 快取（.godot/global_script_class_cache.cfg）與實際原始碼不一致的名稱。

    實測（Godot 4.7.2）：b.gd 的 class_name 改名後、快取未更新時，用到舊名稱的 c.gd 仍然 --check-only 通過（假通過）；
    --import 或編輯器重新掃描後才會報錯。這裡只比對「快取內每一筆」與「本次要檢查的檔案」，約 150 次讀檔。
    """
    cache = read_class_cache()
    if cache is None:
        return set()                      # 沒有快取時用到 class_name 的腳本會 FAIL（不是假通過），由輸出提示處理
    stale: set[str] = set()
    for name, res in cache.items():
        try:
            m = gd_deps.RE_CLASS.search((PROJ / res[6:]).read_text(encoding="utf-8", errors="replace"))
        except OSError:
            stale.add(name)
            continue
        if not m or m.group(1) != name:
            stale.add(name)
    for res, text in texts.items():
        m = gd_deps.RE_CLASS.search(text)
        if m and cache.get(m.group(1)) != res:
            stale.add(m.group(1))
    return stale


def load_cache() -> dict:
    try:
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_cache(new_entries: dict) -> None:
    """合併寫入（先重讀磁碟上的最新內容，降低多程序互相覆蓋）；唯一暫存檔名，避免兩個程序寫同一個 .tmp。"""
    try:
        now = time.time()
        c = {**load_cache(), **new_entries}
        c = {k: v for k, v in c.items() if isinstance(v, dict) and now - v.get("ts", 0) < CACHE_TTL}
        if len(c) > 5000:
            c = dict(sorted(c.items(), key=lambda kv: -kv[1]["ts"])[:5000])
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix="gd_check_cache.", suffix=".tmp", dir=CACHE_FILE.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(json.dumps(c, ensure_ascii=False))
            os.replace(tmp, CACHE_FILE)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    except OSError:
        pass


# ───────────────────────── 執行檢查 ─────────────────────────

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


def _error_groups(out: str) -> list[tuple[list[str], set[str]]]:
    """把 godot 的錯誤輸出分成「一個錯誤＋它的 at: 行」群組，並抓出群組提到的 res://….gd 路徑。

    注意：Godot 的錯誤走 stderr、print() 走 stdout，run_godot 把兩者串接（stdout 在前），所以錯誤行和
    GDCHK 標記的先後順序不可靠——只能靠『錯誤文字裡提到哪支腳本』來歸屬，不能靠行的位置。"""
    groups: list[list[str]] = []
    cur: list[str] | None = None
    for ln in out.replace("\r", "").split("\n"):
        s = ln.strip()
        if s.startswith(("SCRIPT ERROR:", "ERROR:")):
            cur = [s]
            groups.append(cur)
        elif cur is not None and s and (s.startswith("at:") or ln.startswith((" ", "\t"))):
            cur.append(s)
        else:
            cur = None
    return [(g, set(re.findall(r"res://[^\s\"':()]+?\.gd", " ".join(g)))) for g in groups]


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
    for ln in out.replace("\r", "").split("\n"):
        m = re.match(r"GDCHK\t(PASS|FAIL)\t(.+)$", ln)
        if m:
            verdict[m.group(2)] = m.group(1)
    groups = _error_groups(out)
    # autoload 腳本本身載入失敗：實測（Godot 4.7.2）載入器仍會對依賴它的腳本回 PASS（單例沒註冊成功）→ 不可信
    try:
        autoload_paths = gd_deps.parse_autoloads((PROJ / "project.godot").read_text(encoding="utf-8"))
    except OSError:
        autoload_paths = {}
    broken: dict[str, list[str]] = {}           # autoload 名稱 -> 錯誤行
    for name, res in autoload_paths.items():
        if res.endswith(".gd") and res not in targets:
            errs = [ln for g, paths in groups if res in paths for ln in g[:2]]
            if errs:
                broken[name] = errs
    for it in items:
        v = verdict.get(it["path"])
        mine = [ln for g, paths in groups if it["path"] in paths for ln in g[:2]]
        uses: list[str] = []
        if v == "PASS" and broken:
            try:
                ids = set(RE_WORD.findall((PROJ / it["path"][6:]).read_text(encoding="utf-8", errors="replace")))
            except OSError:
                ids = set()
            uses = [n for n in broken if n in ids]
        if v == "PASS" and uses:
            it.update(status="FAIL", lines=[f"autoload {uses[0]} 的腳本載入失敗，依賴它的腳本 PASS 不可信："] + broken[uses[0]][:3],
                      note="autoload 腳本載入失敗")
        elif v == "PASS":
            it.update(status="PASS", note="autoload 單例已註冊條件下通過（--check-only 的誤報）", lines=[])
        elif v == "FAIL":
            it.update(status="FAIL", lines=(mine or ["load() 後 can_instantiate()=false"])[:8], note="第二意見確認失敗")
        else:
            it.update(status="ERROR", lines=["第二意見沒有回報此檔（rc=%s）：%s" % (rc, out[-200:].replace("\n", " "))])


def _sha(p: Path) -> str | None:
    try:
        return hashlib.sha256(p.read_bytes()).hexdigest()[:20]
    except OSError:
        return None


def run_checks_ex(paths: list[Path], jobs: int, timeout: float, use_cache: bool, godot_info: dict | None = None) -> tuple[list[dict], dict]:
    g = godot_info or resolve_godot()
    meta: dict = {"godot": g, "drift": [], "cache_written": 0, "cache_hits": 0, "checked": 0}
    if not g["ok"]:
        return [{"path": to_target(p)[0], "status": "ERROR", "lines": [g["error"]], "secs": 0, "cached": False, "note": ""} for p in paths], meta
    godot, ver = g["path"], g["version"]
    autoloads = autoload_names()
    snap0 = project_snapshot()
    sig0 = signature(snap0)
    results: list[dict] = []
    todo: list[tuple[Path, str, str]] = []
    texts: dict[str, str] = {}
    cache = load_cache() if use_cache else {}
    ccfp = class_cache_fingerprint()
    now = time.time()
    for p in paths:
        target, inside = to_target(p)
        if not p.is_file():
            results.append({"path": target, "status": "ERROR", "lines": ["檔案不存在"], "secs": 0, "cached": False, "note": ""})
            continue
        if inside and is_gdignored(p):
            results.append({"path": target, "status": "SKIP", "lines": [], "secs": 0, "cached": False, "note": "在 .gdignore 目錄內，res:// 無法載入"})
            continue
        data = p.read_bytes()
        h = hashlib.sha256(data).hexdigest()[:20]
        text = data.decode("utf-8", "replace")
        if inside:
            texts[target] = text
        key = ""
        if use_cache:
            dfp = dep_fingerprint(text, target) if inside else ""
            key = f"{h}|{target}|{ver}|{sig0}|{dfp}|{ccfp}"
            hit = cache.get(key)
            if hit and now - hit["ts"] < CACHE_TTL and hit["res"].get("status") == "PASS":
                results.append({**hit["res"], "path": target, "cached": True, "secs": 0})
                meta["cache_hits"] += 1
                continue
        todo.append((p, key, h))
    with ThreadPoolExecutor(max(1, min(jobs, len(todo) or 1))) as ex:
        fresh = list(ex.map(lambda t: check_one(godot, t[0], autoloads, timeout), todo))
    second_opinion(godot, [r for r in fresh if r["status"] == "NEEDS_SECOND"], timeout)
    meta["checked"] = len(fresh)
    # ── 併發保護：檢查期間有沒有人改檔（全部命中快取＝沒有跑任何檢查，不需要第二次快照）──
    snap1 = project_snapshot() if todo else snap0
    drift = sorted(k for k in set(snap0) | set(snap1) if snap0.get(k) != snap1.get(k))
    meta["drift"] = drift
    affected: set[str] = set()
    all_affected = "project.godot" in drift
    if drift and not all_affected:
        idx = gd_deps.DepIndex(PROJ)
        for d in drift:
            rp = "res://" + d
            affected.add(rp)
            affected |= idx.direct_dependents(rp)
    stale_msg_file = "檢查期間這個檔案的內容被修改（其他 Session／編輯器正在寫入？）——此結果不可信，請重跑"
    store_candidates: list[tuple[str, dict]] = []
    for (p, key, h), r in zip(todo, fresh):
        if not r.get("inside_project", True):
            r["note"] = (r.get("note", "") + " 專案外檔案：autoload／class_name 解析可能與專案內不同").strip()
        if _sha(p) != h:
            r.update(status="STALE", lines=[stale_msg_file])
        elif use_cache and key and not drift:
            store_candidates.append((key, r))
        results.append(r)
    if drift:
        why = "project.godot" if all_affected else ", ".join(drift[:4])
        for r in results:
            if r["status"] == "PASS" and (all_affected or r["path"] in affected):
                r.update(status="STALE", cached=False, lines=[f"檢查期間相依檔案被修改（{why}）——PASS 不可信，請重跑"])
    # ── class_name 快取過期：用到過期名稱的 PASS 不可信；FAIL 若提到過期名稱則補註 ──
    stale = stale_class_names(texts) if texts else set()
    meta["stale_classes"] = sorted(stale)
    cache_missing = read_class_cache() is None
    for r in results:
        txt = texts.get(r["path"])
        if r["status"] == "PASS" and stale and txt and stale & set(RE_WORD.findall(txt)):
            names = ", ".join(sorted(stale & set(RE_WORD.findall(txt)))[:4])
            r.update(status="STALE", cached=False, lines=[f"class_name 快取過期（{names}）：.godot/global_script_class_cache.cfg 與原始碼不一致，"
                                                          f"--check-only 對這些名稱的結果不可信。請開編輯器或跑 godot --headless --path <專案> --import 後重跑"])
        elif r["status"] == "FAIL" and any("Could not find type" in ln or "not declared in the current scope" in ln for ln in r.get("lines", [])):
            if cache_missing:
                r["note"] = (r.get("note", "") + " class 快取檔不存在（.godot/global_script_class_cache.cfg）：class_name 相關錯誤可能是誤報，先 --import").strip()
            elif stale:
                r["note"] = (r.get("note", "") + f" class 快取過期（{', '.join(sorted(stale)[:4])}）：這個錯誤可能是誤報或漏報，先 --import").strip()
    if to_store_final := {k: {"ts": now, "res": {kk: vv for kk, vv in r.items() if kk not in ("cached", "secs")}}
                          for k, r in store_candidates if r["status"] == "PASS"}:   # 全部修正（STALE 等）之後才決定存哪些
        save_cache(to_store_final)
        meta["cache_written"] = len(to_store_final)
    return sorted(results, key=lambda r: r["path"]), meta


def run_checks(paths: list[Path], jobs: int, timeout: float, use_cache: bool) -> list[dict]:
    return run_checks_ex(paths, jobs, timeout, use_cache)[0]


# ───────────────────────── 輸出 ─────────────────────────

COUNT_KEYS = ("PASS", "FAIL", "ERROR", "STALE", "SKIP")


def render(results: list[dict]) -> str:
    out = []
    for r in results:
        tag = r["status"]
        extra = " (快取)" if r.get("cached") else (f" {r['secs']}s" if r.get("secs") else "")
        note = f"  # {r['note']}" if r.get("note") else ""
        out.append(f"{tag:5s} {r['path']}{extra}{note}")
        for ln in r.get("lines", [])[:6]:
            out.append("      | " + ln[:200])
    c = {s: sum(1 for r in results if r["status"] == s) for s in COUNT_KEYS}
    out.append(f"gd_check: {len(results)} 檔 — " + " / ".join(f"{k} {c[k]}" for k in COUNT_KEYS))
    return "\n".join(out)


def coverage_text(plan: dict, meta: dict | None = None) -> str:
    mode = plan["mode"]
    n_t = len(plan["targets"])
    nd = len(plan["dependents"])
    if mode == "all":
        s = f"覆蓋範圍：全專案 {n_t} 個 .gd（略過 .gdignore）。不含：場景／資源載入、執行期行為。"
    elif mode == "changed→all":
        s = f"覆蓋範圍：全專案 {n_t} 個 .gd（因 project.godot 的編譯相關設定變動而升級）。"
    elif mode == "explicit":
        s = f"覆蓋範圍：指定的檔案 {n_t - nd} 個" + (f" ＋ 直接相依 {nd} 個" if nd else "；未檢查相依腳本（加 --dependents 納入直接相依）") + "。"
    else:
        s = (f"覆蓋範圍：變動的 .gd {n_t - nd} 個 ＋ 直接相依 .gd {nd} 個（{plan['seeds']} 個變動／刪除的檔案作為種子；"
             f"依賴判定＝preload／extends 路徑（編譯期）、class_name、autoload 名稱的文字索引，寧多勿漏）。")
    if mode in ("changed", "explicit") and plan["depth"] <= 1 and (nd or mode == "changed"):
        s += " 未涵蓋：間接相依（深度≥2，--dependents-depth 2）、經由場景／資源轉手的相依、動態 load()／拼接路徑。完整保證用 --all。"
    if mode != "changed→all":
        s += (" Godot 本身的限制：相依腳本『移除／改名方法』預設只是 UNSAFE 警告，--check-only 不會報錯（簽名、回傳型別、class_name、"
              "preload 路徑、autoload 註冊的變動才抓得到）。")
    if plan["incomplete"]:
        s += f" ⚠ 相依腳本超過上限，另有 {plan['unchecked_dependents']} 個未檢查（調高 --dependents-limit 或用 --all）——覆蓋不完整，視同 exit 2。"
    for n in plan["notes"]:
        s += f"\n注意：{n}"
    if meta:
        if meta.get("drift"):
            s += f"\n⚠ 檢查期間專案有 {len(meta['drift'])} 個檔案被修改（{', '.join(meta['drift'][:5])}…）：本次不寫快取；受影響的 PASS 已標為 STALE。"
        s += f"\n快取：命中 {meta.get('cache_hits', 0)}，實際檢查 {meta.get('checked', 0)}，寫入 {meta.get('cache_written', 0)}（只存 PASS）。"
    return s


def exit_code(results: list[dict], plan: dict | None = None) -> int:
    if any(r["status"] == "FAIL" for r in results):
        return 1
    if any(r["status"] in ("ERROR", "STALE") for r in results):
        return 2
    if plan and plan.get("incomplete"):
        return 2
    return 0


def write_last_run(g: dict, plan: dict, results: list[dict], meta: dict) -> None:
    try:
        LAST_RUN_FILE.parent.mkdir(parents=True, exist_ok=True)
        rec = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "godot": {k: g.get(k) for k in ("path", "version", "source", "required", "ok", "error")},
               "mode": plan["mode"], "targets": len(plan["targets"]), "dependents": len(plan["dependents"]),
               "incomplete": plan["incomplete"], "counts": {k: sum(1 for r in results if r["status"] == k) for k in COUNT_KEYS},
               "cache_hits": meta.get("cache_hits"), "drift": meta.get("drift", [])[:20]}
        LAST_RUN_FILE.write_text(json.dumps(rec, ensure_ascii=False, indent=1), encoding="utf-8")
    except OSError:
        pass


# ───────────────────────── 自測（純解析＋版本鎖定；Godot 整合場景見 test_gd_check.py） ─────────────────────────

def _selftest() -> int:
    ok = True

    def case(name: str, cond: bool) -> None:
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name)
        ok = ok and cond

    # --- 輸出分類（不需 godot）---
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
    case("exit_code：有 FAIL → 1", exit_code([{"status": "FAIL"}, {"status": "PASS"}]) == 1)
    case("exit_code：只有 ERROR → 2", exit_code([{"status": "ERROR"}, {"status": "PASS"}]) == 2)
    case("exit_code：STALE → 2（不是通過）", exit_code([{"status": "STALE"}, {"status": "PASS"}]) == 2)
    case("exit_code：覆蓋不完整 → 2", exit_code([{"status": "PASS"}], {"incomplete": True}) == 2)
    case("exit_code：全 PASS → 0", exit_code([{"status": "PASS"}]) == 0)

    # --- 版本比對 ---
    case("4.7.2.stable.official.ed1daf0bf 符合 4.7.2", version_matches("4.7.2.stable.official.ed1daf0bf", "4.7.2")[0])
    case("4.8.0.stable 不符合 4.7.2（不因為較新而接受）", not version_matches("4.8.0.stable.official.abcdef0", "4.7.2")[0])
    case("4.7.1.stable 不符合 4.7.2", not version_matches("4.7.1.stable.official.abcdef0", "4.7.2")[0])
    case("4.7.2.rc1 不是 stable → 不符合", not version_matches("4.7.2.rc1.official.abcdef0", "4.7.2")[0])
    case("要求只寫 4.7 時不比 patch", version_matches("4.7.5.stable.official.abcdef0", "4.7")[0])
    case("無法解析的版本字串 → 不符合", not version_matches("hello", "4.7.2")[0])

    # --- 選擇機制（用假的 godot.cmd；不改全域 PATH，只在本程序內暫時改環境）---
    with tempfile.TemporaryDirectory() as td:
        f48 = Path(td) / "godot48.cmd"
        f48.write_text("@echo off\r\necho 4.8.0.stable.official.deadbeef1\r\n", encoding="ascii")
        saved = {k: os.environ.get(k) for k in ("GODOT_BIN", "GODOT_REQUIRED_VERSION", "PATH")}
        try:
            os.environ["GODOT_BIN"] = str(Path(td) / "nope.exe")
            g = resolve_godot()
            case("GODOT_BIN 指到不存在 → 報錯，不退回其他版本", (not g["ok"]) and "不會自動改用" in g["error"])
            os.environ["GODOT_BIN"] = str(f48)
            g = resolve_godot()
            case("GODOT_BIN 是 4.8.0 → 版本不符、報出實際版本、不退回 4.7.2", (not g["ok"]) and g["version"].startswith("4.8.0") and "4.7.2" in g["error"])
            os.environ["GODOT_REQUIRED_VERSION"] = "4.8.0"
            g = resolve_godot()
            feat = project_feature_version()
            case("明確設 GODOT_REQUIRED_VERSION=4.8.0 才接受 4.8.0；但與專案 features 不一致仍會報",
                 ((not g["ok"]) and "config/features" in g["error"]) if feat else g["ok"])
            os.environ.pop("GODOT_REQUIRED_VERSION")
            os.environ.pop("GODOT_BIN")
            os.environ["PATH"] = td + os.pathsep + os.environ.get("PATH", "")
            Path(td, "godot.cmd").write_text("@echo off\r\necho 4.8.0.stable.official.deadbeef1\r\n", encoding="ascii")
            g = resolve_godot()
            case("PATH 上有較新的 godot(4.8.0) → 被略過並列出，不被選用",
                 any(s["version"] and s["version"].startswith("4.8.0") for s in g["skipped"]) and (not g["ok"] or g["version"].startswith("4.7.2")))
        finally:
            for k, v in saved.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
    g = resolve_godot()
    case("目前環境解析結果符合要求版本（有路徑與版本）", g["ok"] and bool(g["path"]) and g["version"].startswith(required_godot()))

    if not g["ok"]:
        print("FAIL 找不到符合版本的 godot，無法做整合測試：", g["error"])
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
        bad_g = {"ok": False, "error": "測試：找不到 godot", "path": None, "version": None}
        nb, _ = run_checks_ex([good], 1, 30, False, godot_info=bad_g)
        case("版本／路徑不合 → ERROR（exit 2，不是 PASS）", nb[0]["status"] == "ERROR" and exit_code(nb) == 2)
    main_gd = PROJ / "scripts" / "main.gd"
    if main_gd.exists():
        m = run_checks([main_gd], 1, 60, False)
        case("autoload 誤報案例 scripts/main.gd → 第二意見 PASS", m[0]["status"] == "PASS")
    print("selftest:", "ALL PASS" if ok else "FAILED")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="改完 .gd 的快速檢查（--check-only＋autoload 感知第二意見＋反向依賴）")
    ap.add_argument("files", nargs="*")
    ap.add_argument("--all", action="store_true", help="全專案所有 .gd（略過 .gdignore）")
    ap.add_argument("--no-cache", action="store_true")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--project", help="目標 Godot 專案資料夾（預設 repo 的 godot/；也可用 GD_CHECK_PROJECT）")
    ap.add_argument("--which-godot", action="store_true", help="只印選到的 godot 路徑與版本")
    ap.add_argument("--plan", action="store_true", help="只印要檢查哪些檔與覆蓋範圍，不啟動 godot")
    dg = ap.add_mutually_exclusive_group()
    dg.add_argument("--dependents", action="store_true", help="指定檔案時也納入直接相依")
    dg.add_argument("--no-dependents", action="store_true", help="預設模式也不納入相依")
    ap.add_argument("--dependents-depth", type=int, default=1, help="相依深度（預設 1＝直接相依）")
    ap.add_argument("--dependents-limit", type=int, default=200, help="相依腳本數量上限；超過則標示覆蓋不完整")
    a = ap.parse_args(argv)
    if a.project:
        set_project(a.project)
    if a.selftest:
        return _selftest()
    g = resolve_godot()
    if a.which_godot:
        print(godot_header(g))
        return 0 if g["ok"] else 2
    deps_mode = "on" if a.dependents else ("off" if a.no_dependents else "auto")
    try:
        plan = build_plan(a.files, a.all, deps_mode, a.dependents_depth, a.dependents_limit)
    except RuntimeError as e:
        print(f"gd_check: {e}", file=sys.stderr)
        return 2
    log = sys.stderr if a.json else sys.stdout
    print(godot_header(g), file=log)
    if a.plan:
        print(f"mode={plan['mode']} 目標 {len(plan['targets'])} 檔（相依 {len(plan['dependents'])}）", file=log)
        for k, v in list(plan["dependents"].items())[:40]:
            print(f"  + {k}  # {v}", file=log)
        print(coverage_text(plan), file=log)
        return 0
    if not plan["targets"]:
        print("gd_check: 沒有需要檢查的 .gd（無相對 HEAD 的變動）", file=log)
        print(coverage_text(plan), file=log)
        return 2 if plan["incomplete"] else 0
    results, meta = run_checks_ex(plan["targets"], a.jobs, a.timeout, not a.no_cache, godot_info=g)
    print(json.dumps(results, ensure_ascii=False, indent=1) if a.json else render(results))
    print(coverage_text(plan, meta), file=sys.stderr if a.json else sys.stdout)
    write_last_run(g, plan, results, meta)
    return exit_code(results, plan)


if __name__ == "__main__":
    sys.exit(main())
