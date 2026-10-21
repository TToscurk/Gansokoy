#!/usr/bin/env python
"""gd_deps — 低成本反向依賴索引（文字級，不是 GDScript 語言伺服器）。

用途：gd_check 在「某檔被改」時，找出可能被它影響的其他 .gd，一併重新檢查。
成本：全專案約 1 秒（1457 個 .gd：讀檔 0.15 秒＋斷詞 0.45 秒）。

判定「A 依賴 B」的證據（都是編譯期會解析的東西）：
  1. A 內有「編譯期」字面路徑指到 B：preload("res://b.gd")、extends "res://b.gd"（相對路徑以 A 所在資料夾解析）。
     load("…")、普通字串常數只有執行期才用，--check-only 不會因它們失敗，不算相依（快取指紋仍會把它們算進去）。
  2. B 宣告 class_name X，且 A 內出現識別字 X（extends X、X.new()、型別標註 var a: X …）。
  3. B 是 project.godot [autoload] 的腳本，名稱 N，且 A 內出現識別字 N。

刻意「寧多勿漏」：註解／字串裡的同名文字也算相依（多查幾檔沒有壞處；漏查才危險）。

已知不涵蓋（呼叫端必須在報告中標明）：
  - 動態路徑：load(變數)、字串拼接、get_node("/root/Name") 這類執行期才解析的東西
    （--check-only 本來就不會檢查它們）。
  - 經由場景／資源轉手：A preload 場景 S，S 內部引用的資源或腳本被改——本索引不解析 .tscn/.tres 內容。
  - uid:// 路徑（目前專案 0 處使用）。
  - 深度：預設只回傳直接相依；間接相依需 depth>=2，成本隨之放大。
"""
from __future__ import annotations

import os
import posixpath
import re
from pathlib import Path

RE_CLASS = re.compile(r"(?m)^[ \t]*class_name[ \t]+([^\W\d]\w*)")      # GDScript 允許 Unicode 識別字（專案有中文 class_name）
RE_QUOTED_RES = re.compile(r"""["'](res://[^"'\r\n]+)["']""")
RE_PATH_CALL = re.compile(r"""\b(?:preload|load)\([ \t]*["']([^"'\r\n]+)["']""")
RE_PRELOAD = re.compile(r"""\bpreload\([ \t]*["']([^"'\r\n]+)["']""")        # 編譯期引用（檔案不存在 → 編譯錯誤）
RE_EXTENDS_STR = re.compile(r"""(?m)^[ \t]*extends[ \t]+["']([^"'\r\n]+)["']""")
RE_IDENT = re.compile(r"[^\W\d]\w*")
RE_AUTOLOAD_SECTION = re.compile(r"(?ms)^\[autoload\]\s*$(.*?)(?=^\[|\Z)")


def parse_autoloads(project_godot_text: str) -> dict[str, str]:
    """{名稱: res:// 路徑}（去掉單例標記 *）。"""
    m = RE_AUTOLOAD_SECTION.search(project_godot_text)
    out: dict[str, str] = {}
    if not m:
        return out
    for ln in m.group(1).splitlines():
        if "=" not in ln or ln.lstrip().startswith(";"):
            continue
        k, v = ln.split("=", 1)
        out[k.strip()] = v.strip().strip('"').lstrip("*")
    return out


def resolve_ref(script_res: str, raw: str) -> str | None:
    """把字面字串解析成 res:// 路徑；不是檔案路徑（user://、http、拼接殘渣）回傳 None。"""
    if not raw or any(c in raw for c in "+{}\n") or raw.startswith(("user://", "http", "uid://")):
        return None
    if raw.startswith("res://"):
        return raw
    if "://" in raw or raw.startswith("%"):
        return None
    base = posixpath.dirname(script_res[len("res://"):])
    joined = posixpath.normpath(posixpath.join(base, raw))
    if joined.startswith(".."):
        return None
    return "res://" + joined


def extract(text: str, script_res: str) -> tuple[str | None, set[str], set[str], set[str]]:
    """回傳 (class_name, 所有引用的 res:// 路徑, 編譯期引用路徑, 識別字集合)。

    『所有引用』＝任何被引號包住的 res:// 字串＋preload/load/extends 的路徑（含相對路徑）——給快取指紋用，寧多勿漏。
    『編譯期引用』＝只有 preload("…") 與 extends "…"：目標不存在會在編譯期報錯，--check-only 看得到；
    load("…")、字串常數只在執行期才用，--check-only 不會因它們失敗，所以不當成「相依」（否則改一個場景會牽連所有 load 它的工具腳本）。"""
    m = RE_CLASS.search(text)
    refs: set[str] = set(RE_QUOTED_RES.findall(text))
    hard: set[str] = set()
    for rx in (RE_PATH_CALL, RE_EXTENDS_STR):
        for raw in rx.findall(text):
            r = resolve_ref(script_res, raw)
            if r:
                refs.add(r)
    for rx in (RE_PRELOAD, RE_EXTENDS_STR):
        for raw in rx.findall(text):
            r = resolve_ref(script_res, raw)
            if r:
                hard.add(r)
    return (m.group(1) if m else None), refs, hard, set(RE_IDENT.findall(text))


def refs_of(text: str, script_res: str) -> set[str]:
    return extract(text, script_res)[1]


class DepIndex:
    def __init__(self, proj: Path, head_reader=None):
        """proj = 含 project.godot 的資料夾。head_reader(res_path)->str|None 用來讀「已刪除檔」在 HEAD 的內容（可省略）。"""
        self.proj = Path(proj)
        self.head_reader = head_reader
        self.class_of: dict[str, str] = {}      # 名稱 -> res 路徑
        self.name_of: dict[str, str] = {}       # res 路徑 -> class_name
        self.autoload: dict[str, str] = {}      # 名稱 -> res 路徑
        self.refs_rev: dict[str, set[str]] = {}   # 被引用路徑 -> 引用它的腳本
        self.scripts: set[str] = set()
        self.idents: dict[str, set[str]] = {}     # 腳本 -> 出現的識別字（任何名稱都能查，含已刪除的 class／autoload）
        self._build()

    @staticmethod
    def _res(proj: Path, p: Path) -> str:
        return "res://" + p.relative_to(proj).as_posix()

    def _build(self) -> None:
        try:
            self.autoload = parse_autoloads((self.proj / "project.godot").read_text(encoding="utf-8"))
        except OSError:
            self.autoload = {}
        parsed: dict[str, tuple[set[str], set[str]]] = {}      # 腳本 -> (編譯期引用, 識別字)
        for root, dirs, fs in os.walk(self.proj):
            dirs[:] = [d for d in dirs if d != ".godot"]
            if ".gdignore" in fs:
                dirs[:] = []
                continue
            for f in fs:
                if not f.endswith(".gd"):
                    continue
                p = Path(root) / f
                try:
                    text = p.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                rp = self._res(self.proj, p)
                cn, _all_refs, refs, ids = extract(text, rp)
                self.scripts.add(rp)
                parsed[rp] = (refs, ids)
                if cn:
                    self.class_of[cn] = rp
                    self.name_of[rp] = cn
        for rp, (refs, ids) in parsed.items():
            self.idents[rp] = ids
            for r in refs:
                self.refs_rev.setdefault(r, set()).add(rp)

    def users_of(self, name: str) -> set[str]:
        """哪些腳本出現識別字 name。已刪除的 class_name／autoload 名稱也查得到（不依賴「目前存在」的名單）。"""
        return {rp for rp, ids in self.idents.items() if name in ids}

    def names_for(self, res_path: str) -> set[str]:
        """這個檔案對外提供的名稱：class_name、autoload 名稱（已刪除檔用 HEAD 內容回推 class_name）。"""
        names = set()
        cn = self.name_of.get(res_path)
        if cn is None and self.head_reader and res_path not in self.scripts and res_path.endswith(".gd"):
            old = self.head_reader(res_path)
            if old:
                cn = RE_CLASS.search(old).group(1) if RE_CLASS.search(old) else None
        if cn:
            names.add(cn)
        names |= {n for n, p in self.autoload.items() if p == res_path}
        return names

    def direct_dependents(self, res_path: str, extra_names: set[str] = frozenset()) -> set[str]:
        out = set(self.refs_rev.get(res_path, ()))
        for n in self.names_for(res_path) | set(extra_names):
            out |= self.users_of(n)
        out.discard(res_path)
        return out

    def dependents(self, seeds: set[str], depth: int = 1, extra_names: set[str] = frozenset()) -> dict[str, str]:
        """{依賴者 res 路徑: 原因}。seeds 本身不會出現在結果裡（呼叫端自己已經要檢查它們）。"""
        found: dict[str, str] = {}
        frontier = set(seeds)
        seen = set(seeds)
        for level in range(max(1, depth)):
            nxt: set[str] = set()
            for s in sorted(frontier):
                extra = extra_names if level == 0 else frozenset()
                for d in self.direct_dependents(s, extra):
                    if d not in seen:
                        found[d] = f"依賴 {s}" + ("" if level == 0 else f"（間接，第 {level + 1} 層）")
                        nxt.add(d)
                        seen.add(d)
            frontier = nxt
            if not frontier:
                break
        return found
