#!/usr/bin/env python
"""safe_replace — 精確字串取代，強制檢查匹配次數。

為什麼有這支：`s = s.replace(old, new)` 在 old 找不到時不會報錯，檔案原封不動寫回，
agent 以為已改完。本工具在匹配次數 != 預期時一律報錯（exit 1），且不寫檔。

特性
  - 預設預期恰好 1 次（--expect N 可改）；0 次或多次 → 報錯並列出行號，不動檔案。
  - 逐位元組讀寫（不做換行轉換）；old/new 用 LF 但檔案是 CRLF 時自動換成 CRLF 匹配，
    寫回後不會混入裸 LF。tab、BOM、CJK 原樣保留。
  - 多筆編輯 all-or-nothing（replace_many）；寫檔用暫存檔 + os.replace，並回讀驗證。

用法（腳本內）
    import sys; sys.path.insert(0, "tools/dev")        # 從 repo 根目錄執行
    from safe_replace import replace_exact, replace_many
    replace_exact("godot/x.gd", old_text, new_text)                 # 預期 1 次
    replace_many("godot/x.gd", [(a1, b1, 1), (a2, b2, 3)])          # 全成功才寫檔

用法（CLI，多行內容用檔案）
    python tools/dev/safe_replace.py FILE --old-file old.txt --new-file new.txt [--expect N] [--dry-run]
    python tools/dev/safe_replace.py --selftest
"""
from __future__ import annotations

import argparse
import os
import sys
import tempfile
import time


class ReplaceError(Exception):
    """匹配次數不符、old==new、編碼錯誤或回讀驗證失敗。"""


def _line_of(text: str, pos: int) -> int:
    return text.count("\n", 0, pos) + 1


def _positions(text: str, needle: str, limit: int = 50) -> list[int]:
    out, i = [], 0
    while len(out) < limit:
        j = text.find(needle, i)
        if j < 0:
            break
        out.append(j)
        i = j + max(1, len(needle))
    return out


def _candidates(text: str, old: str, new: str) -> list[tuple[str, str, str]]:
    c = [("exact", old, new)]
    if "\r\n" in text and "\r" not in old and "\n" in old:
        c.append(("lf->crlf", old.replace("\n", "\r\n"), new.replace("\n", "\r\n")))
    if "\r\n" in old and "\r\n" not in text:
        c.append(("crlf->lf", old.replace("\r\n", "\n"), new.replace("\r\n", "\n")))
    return c


def _zero_hint(text: str, old: str) -> str:
    s = old.strip()
    if s and s != old and text.count(s):
        return f"（去掉首尾空白後的內容出現 {text.count(s)} 次——檢查縮排／結尾換行）"
    first = next((ln.strip() for ln in old.splitlines() if ln.strip()), "")
    if first:
        lines = [_line_of(text, p) for p in _positions(text, first, 3)]
        if lines:
            return f"（old 的第一個非空行在第 {lines} 行出現過，但整段不連續相符）"
    return ""


def _apply(text: str, old: str, new: str, expect: int, tag: str) -> tuple[str, str]:
    if old == "":
        raise ReplaceError(f"{tag}: old 是空字串")
    if old == new:
        raise ReplaceError(f"{tag}: old 與 new 相同，沒有東西可改")
    hits = []
    for label, o, n in _candidates(text, old, new):
        c = text.count(o)
        if c:
            hits.append((label, o, n, c))
    if len(hits) > 1:
        raise ReplaceError(f"{tag}: 檔案換行混用，LF/CRLF 兩種寫法都匹配到（{[(h[0], h[3]) for h in hits]}），請縮小 old 範圍")
    if not hits:
        raise ReplaceError(f"{tag}: 匹配 0 次，預期 {expect} 次 {_zero_hint(text, old)}")
    label, o, n, count = hits[0]
    if count != expect:
        lines = [_line_of(text, p) for p in _positions(text, o, 8)]
        raise ReplaceError(f"{tag}: 匹配 {count} 次，預期 {expect} 次；位置（行）{lines}")
    return text.replace(o, n), label


def _read(path: str) -> tuple[bytes, str]:
    with open(path, "rb") as f:
        data = f.read()
    try:
        return data, data.decode("utf-8")
    except UnicodeDecodeError as e:
        raise ReplaceError(f"{path}: 不是 UTF-8（{e}）；本工具不處理其他編碼") from e


def _write_atomic(path: str, data: bytes) -> None:
    d = os.path.dirname(os.path.abspath(path))
    mode = os.stat(path).st_mode
    fd, tmp = tempfile.mkstemp(prefix=".sr_", dir=d)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        for attempt in range(5):  # Windows：編輯器／防毒短暫鎖檔
            try:
                os.replace(tmp, path)
                return
            except PermissionError:
                if attempt == 4:
                    raise
                time.sleep(0.5)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def replace_many(path: str, edits: list[tuple[str, str, int]], dry_run: bool = False) -> dict:
    """依序套用多筆 (old, new, expect)；任何一筆不符 → 丟 ReplaceError，檔案不動。"""
    before_bytes, text = _read(path)
    modes = []
    for i, (old, new, expect) in enumerate(edits, 1):
        text, mode = _apply(text, old, new, expect, f"{path} 第{i}筆")
        modes.append(mode)
    after_bytes = text.encode("utf-8")
    if not dry_run:
        _write_atomic(path, after_bytes)
        if open(path, "rb").read() != after_bytes:
            raise ReplaceError(f"{path}: 寫入後回讀與預期不一致")
    return {"path": path, "edits": len(edits), "eol_modes": modes, "bytes_before": len(before_bytes),
            "bytes_after": len(after_bytes), "dry_run": dry_run}


def replace_exact(path: str, old: str, new: str, expect: int = 1, dry_run: bool = False) -> dict:
    return replace_many(path, [(old, new, expect)], dry_run=dry_run)


def _selftest() -> int:
    ok = True

    def case(name: str, cond: bool) -> None:
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name)
        ok = ok and cond

    def expect_err(fn) -> bool:
        try:
            fn()
        except ReplaceError:
            return True
        return False

    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "a.gd")

        def put(b: bytes) -> None:
            with open(p, "wb") as f:
                f.write(b)

        def get() -> bytes:
            return open(p, "rb").read()

        put("x := 1\n\tfoo()\n\tfoo()\n".encode())
        r = replace_exact(p, "x := 1", "x := 2")
        case("單次匹配成功", get() == "x := 2\n\tfoo()\n\tfoo()\n".encode() and r["edits"] == 1)

        raw = get()
        case("0 次匹配 → 報錯且檔案不動", expect_err(lambda: replace_exact(p, "nope", "y")) and get() == raw)
        case("匹配 2 次但預期 1 → 報錯且檔案不動", expect_err(lambda: replace_exact(p, "foo()", "bar()")) and get() == raw)
        replace_exact(p, "foo()", "bar()", expect=2)
        case("expect=2 且恰好 2 次 → 成功", get().count(b"bar()") == 2)
        case("old==new → 報錯", expect_err(lambda: replace_exact(p, "bar()", "bar()", expect=2)))

        put("a\r\n\tb\r\n\tc\r\n".encode())
        replace_exact(p, "\tb\n\tc", "\tB\n\tC")
        g = get()
        case("CRLF 檔 + LF 的 old：匹配成功、無裸 LF、tab 保留", g == "a\r\n\tB\r\n\tC\r\n".encode() and g.count(b"\n") == g.count(b"\r\n"))

        put("\ufeff中文 變數 := 1\n".encode())
        replace_exact(p, "變數 := 1", "變數 := 2")
        case("BOM + CJK 原樣保留", get() == "\ufeff中文 變數 := 2\n".encode())

        put(b"a=1\nb=2\n")
        raw = get()
        case("多筆 all-or-nothing：第二筆失敗 → 第一筆也不寫",
             expect_err(lambda: replace_many(p, [("a=1", "a=9", 1), ("zzz", "q", 1)])) and get() == raw)
        replace_many(p, [("a=1", "a=9", 1), ("b=2", "b=8", 1)])
        case("多筆全成功 → 寫入", get() == b"a=9\nb=8\n")

        put(b"x\r\ny\nx\ny\n")
        raw = get()
        case("換行混用且 LF/CRLF 兩種都匹配 → 報錯、檔案不動", expect_err(lambda: replace_exact(p, "x\ny", "X\nY")) and get() == raw)
        put(b"k=1\n")
        replace_exact(p, "k=1", "k=2", dry_run=True)
        case("dry-run 不寫檔", get() == b"k=1\n")
        put(b"\xff\xfe bad")
        case("非 UTF-8 → 報錯", expect_err(lambda: replace_exact(p, "bad", "good")))

        # --- 跳脫字元原樣保留 ---
        # Hermes 的 patch 工具會把 new_string 裡的「反斜線+t／r」轉成真正的 TAB／CR（條件：被匹配的區段本來就含 TAB／CR）。
        # 這支工具不做任何跳脫解讀；下面用 chr() 組字串，避免這個測試檔本身被任何工具轉換。
        BS, TAB, CR, LF = chr(92), chr(9), chr(13), chr(10)

        def exact(name: str, start: str, old: str, new: str, expected: str) -> None:
            put(start.encode("utf-8"))
            try:
                replace_exact(p, old, new)
                case(name, get() == expected.encode("utf-8"))
            except ReplaceError as e:
                case(name + f"（意外報錯 {e}）", False)

        gd_old = TAB + 'print("old")'
        exact("TAB 縮排 LF 檔：new 內的 反斜線+t 原樣保留（patch 工具會轉成 TAB）",
              "f():" + LF + gd_old + LF + TAB + "pass" + LF, gd_old, TAB + 'print("a' + BS + 'tb")',
              "f():" + LF + TAB + 'print("a' + BS + 'tb")' + LF + TAB + "pass" + LF)
        exact("TAB 縮排 CRLF 檔：反斜線+t 原樣保留、行尾仍是 CRLF",
              "f():" + CR + LF + gd_old + CR + LF + TAB + "pass" + CR + LF, gd_old, TAB + 'print("a' + BS + 'tb")',
              "f():" + CR + LF + TAB + 'print("a' + BS + 'tb")' + CR + LF + TAB + "pass" + CR + LF)
        exact("兩個反斜線+t（正規表示式／路徑常見）原樣保留（patch 工具會變成『反斜線＋TAB』）",
              "f():" + LF + gd_old + LF, gd_old, TAB + 'print("a' + BS + BS + 'tb")',
              "f():" + LF + TAB + 'print("a' + BS + BS + 'tb")' + LF)
        exact("CRLF 檔多行區段：反斜線+r+反斜線+n 原樣保留（patch 工具會產生裸 CR 並拆行）",
              '[node name="N"]' + CR + LF + 'text = "old"' + CR + LF, '[node name="N"]' + LF + 'text = "old"',
              '[node name="N"]' + LF + 'text = "a' + BS + 'r' + BS + 'nb"',
              '[node name="N"]' + CR + LF + 'text = "a' + BS + 'r' + BS + 'nb"' + CR + LF)
        exact("Unicode（中文、emoji、é）與 反斜線+n 原樣保留",
              "f():" + LF + gd_old + LF, gd_old, TAB + 'print("中文' + BS + 'n🔥é")',
              "f():" + LF + TAB + 'print("中文' + BS + 'n🔥é")' + LF)
        exact("真正的 TAB 與『反斜線+t』同時存在：各自原樣",
              "f():" + LF + gd_old + LF, gd_old, TAB + TAB + 'print("x' + BS + 'ty")',
              "f():" + LF + TAB + TAB + 'print("x' + BS + 'ty")' + LF)
    print("selftest:", "ALL PASS" if ok else "FAILED")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="精確取代並檢查匹配次數")
    ap.add_argument("file", nargs="?")
    ap.add_argument("--old")
    ap.add_argument("--new")
    ap.add_argument("--old-file")
    ap.add_argument("--new-file")
    ap.add_argument("--expect", type=int, default=1)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args(argv)
    if a.selftest:
        return _selftest()
    if not a.file or (a.old is None and not a.old_file) or (a.new is None and not a.new_file):
        ap.error("需要 FILE，以及 --old/--old-file 與 --new/--new-file")
    old = open(a.old_file, encoding="utf-8", newline="").read() if a.old_file else a.old
    new = open(a.new_file, encoding="utf-8", newline="").read() if a.new_file else a.new
    try:
        r = replace_exact(a.file, old, new, expect=a.expect, dry_run=a.dry_run)
    except ReplaceError as e:
        print(f"REPLACE_FAILED {e}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"IO_ERROR {e}", file=sys.stderr)
        return 2
    print(f"OK {r['path']}: 取代 {a.expect} 處（換行模式 {r['eol_modes'][0]}），{r['bytes_before']}→{r['bytes_after']} bytes" + ("（dry-run，未寫檔）" if a.dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
