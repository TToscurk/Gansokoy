#!/usr/bin/env python3
"""核心紅線同步檢查：AGENT_CONSTITUTION.md 是權威，另兩份必須逐字相同。

    python godot/tools/check_constitution_sync.py          # 檢查
    python godot/tools/check_constitution_sync.py --fix    # 用憲法覆寫副本

為什麼需要這支：紅線同時存在三個檔案（憲法本體 + CLAUDE.md + .hermes.md），
2026-09-04 加第 5 條時只改了憲法與 .hermes.md，CLAUDE.md 漏掉，於是
「照哪份走」出現歧義。人工同步遲早會再漏，改成機器檢查。

退出碼：0 = 同步；1 = 不同步（--fix 可修）；2 = 檔案結構壞掉
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "AGENT_CONSTITUTION.md"
COPIES = [ROOT / "CLAUDE.md", ROOT / ".hermes.md"]
HEADING = "核心紅線"


def extract(path: Path, keep_blank: bool = False) -> list[str] | None:
    """取出「核心紅線」區塊的內容行。

    區塊從 '## …核心紅線…' 的下一行開始，到水平線 '---' 或檔尾為止。
    比對時 keep_blank=False（略過空行，避免空行數差異造成假不同步）；
    --fix 重建時 keep_blank=True，否則新格式條文之間的空行會被壓掉。

    ⚠ 不能把 '## ' 當結束條件。憲法改版後每一條紅線自己就是一個 '## '
      標題（'## 1. 重用優先'…），遇到標題就停的話一行都抓不到。
    ⚠ 水平線一定要當結束條件：CLAUDE.md 的紅線後面接的是 '---' 加一段
      散文與「## 核心防護」小節，不擋的話會把它們一起吃進來。

    找不到區塊回傳 None——那是結構問題，不是內容不同步。
    """
    if not path.exists():
        return None
    lines = path.read_bytes().decode("utf-8").splitlines()
    out: list[str] = []
    inside = False
    for line in lines:
        stripped = line.strip()
        if not inside:
            if line.startswith("## ") and HEADING in line:
                inside = True
            continue
        if stripped.startswith("---"):
            break
        if stripped or keep_blank:
            out.append(line.rstrip())
    if not inside:
        return None
    if keep_blank:  # 去掉區塊尾端的空行，交給呼叫端決定間距
        while out and not out[-1].strip():
            out.pop()
    return out


def main() -> int:
    fix = "--fix" in sys.argv
    src = extract(SOURCE)
    if src is None:
        print(f"✗ {SOURCE.name} 找不到「## {HEADING}」小節")
        return 2
    print(f"權威：{SOURCE.name}（{len(src)} 行）")

    bad: list[Path] = []
    for path in COPIES:
        got = extract(path)
        rel = path.relative_to(ROOT)
        if got is None:
            print(f"✗ {rel} 找不到「## {HEADING}」小節")
            bad.append(path)
            continue
        if got == src:
            print(f"✓ {rel}")
            continue
        print(f"✗ {rel} 與憲法不同步（{len(got)} 行 vs {len(src)} 行）")
        for i in range(max(len(src), len(got))):
            a = src[i] if i < len(src) else "(缺這行)"
            b = got[i] if i < len(got) else "(缺這行)"
            if a != b:
                print(f"    第 {i + 1} 行")
                print(f"      憲法：{a}")
                print(f"      副本：{b}")
        bad.append(path)

    if not bad:
        print("══ 三份核心紅線同步 ══")
        return 0

    if not fix:
        print(f"\n══ {len(bad)} 份不同步 ══  用 --fix 以憲法覆寫")
        return 1

    for path in bad:
        # ⚠ 讀取也要繞過換行轉換。read_text() 會把 CRLF 轉成 LF，
        #   之後不管怎麼寫回去，原本的 CRLF 都已經丟失了。
        text = path.read_bytes().decode("utf-8")
        lines = text.splitlines(keepends=True)
        # 重建用的版本要保留條文之間的空行（比對用的 src 已去空行）
        body_src = extract(SOURCE, keep_blank=True) or src
        start = end = None
        for i, line in enumerate(lines):
            if start is None:
                if line.startswith("## ") and HEADING in line:
                    start = i + 1
                continue
            # 與 extract() 同一組結束條件：只認水平線，不認 '## '
            # （紅線本身就是一串 '## ' 標題）
            if line.strip().startswith("---"):
                end = i
                break
        if start is None:
            print(f"✗ {path.name} 沒有區塊可覆寫，請手動處理")
            continue
        if end is None:
            # ⚠ 沒有 '---' 結束標記時**不能**當成「抓到檔尾」。
            #   .hermes.md 曾因此被吃掉整個「工具與證據入口」小節。
            #   紅線區塊必須有明確結尾，否則拒絕自動修。
            print(f"✗ {path.relative_to(ROOT)} 的紅線區塊沒有 '---' 結束標記，")
            print("   自動覆寫會吃掉後面的內容。請先加上分隔線再重跑。")
            continue
        nl = "\r\n" if "\r\n" in text else "\n"
        # ⚠ 換行處理踩過兩次，兩個坑都要避開：
        #   1. 空行：區段結束的空行已含在 lines[start:end] 裡，body 尾端
        #      再加一個就會累積。只補「小節與下一段之間」那一個。
        #   2. CRLF：即使每行自己帶對換行符，write_text() 仍會正規化整份
        #      檔案，把 CRLF 檔寫成 LF、整個 git diff 爆掉。
        #      改成二進位寫入，完全繞過 Python 的換行轉換。
        body = "".join(line + nl for line in body_src) + nl
        lines[start:end] = [body]
        path.write_bytes("".join(lines).encode("utf-8"))
        print(f"→ 已用憲法覆寫 {path.relative_to(ROOT)}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
