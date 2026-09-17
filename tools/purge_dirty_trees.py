"""把 5 種「底部有土台」的樹，從所有應用場景中同位替換成底部乾淨的樹種。

使用者裁定（2026-09-17）：
  下架：櫻花樹、楓樹、普通樹、2大衫、針葉林樹4
  作法：不留空地，用底部乾淨的樹種同位替補（保留原 transform，所以高度/角度不變）

實作要點：
  * landscape/ 全部是 BASE 原點、本地高 0.96–0.99 m，所以 transform 的縮放≈公尺數，
    換 ExtResource 不需重算 transform。
  * 只改 instance=ExtResource("id") 的指向 + 節點名稱前綴；節點結構完全不動。
  * 換完後把沒人引用的 ext_resource 行移除。
  * 節點改名前先確認沒有任何 parent="..." 路徑引用該節點名，否則不改名（避免斷鏈）。
"""
import io
import os
import re
import sys

ROOT = r"D:\神社\shrine\godot"
DRY = "--apply" not in sys.argv

UID = {
    "普通樹": "uid://k25li3c5ewea",
    "大衫": "uid://dkjnpybpp80xw",
    "2大衫": "uid://337s47cfgf4m",
    "針葉樹1": "uid://cm27hy1wguju4",
    "針葉樹2glb": "uid://bmeweqxphe66g",
    "針葉林樹3": "uid://srtn6thryoko",
    "針葉林樹4": "uid://db3m7kuqkp50u",
    "盆樹": "uid://755megjc4ki0",
    "櫻花樹": "uid://dam3c1m628kcv",
    "楓樹": "uid://7w7a17bjvlgx",
    "鎮守之杜": "uid://bwxlquti83b5a",
}

# 下架樹種 -> 替補（多個則依出現順序輪替，增加樹種變化）
REPLACE = {
    "2大衫": ["大衫"],
    "針葉林樹4": ["針葉林樹3"],
    "普通樹": ["鎮守之杜", "針葉樹1"],
    "楓樹": ["針葉樹2glb", "鎮守之杜"],
    "櫻花樹": ["鎮守之杜"],
}

FILES = [
    r"maps\shrine\shrine.tscn",
    r"maps\trail\trail.tscn",
    r"maps\slice\gen\village_infill_trees.tscn",
    r"maps\slice\gen\sakura_trees.tscn",
]

# uid 欄位是選用的：village_infill_trees.tscn 的行沒有 uid
EXT_RE = re.compile(
    r'\[ext_resource type="PackedScene" (?:uid="[^"]+" )?'
    r'path="res://assets/landscape/([^"]+)\.glb" id="([^"]+)"\]')


def process(path):
    full = os.path.join(ROOT, path)
    txt = io.open(full, encoding="utf-8").read()
    orig = txt

    # 1. 收集 landscape 的 ext_resource
    by_name = {}   # name -> id
    by_id = {}     # id -> name
    for m in EXT_RE.finditer(txt):
        by_name[m.group(1)] = m.group(2)
        by_id[m.group(2)] = m.group(1)

    targets = [n for n in REPLACE if n in by_name]
    if not targets:
        return None

    report = {"file": path, "swaps": {}, "renamed": {}, "added": [], "removed": []}

    # 2. 確保替補樹種在本檔有 ext_resource；沒有就新增一行
    needed = set()
    for t in targets:
        needed.update(REPLACE[t])
    seq = 9100
    last_ext = max(m.end() for m in re.finditer(r'^\[ext_resource .*\]$',
                                                txt, re.M))
    additions = []
    for name in sorted(needed):
        if name in by_name:
            continue
        seq += 1
        new_id = "%d_purge" % seq
        additions.append(
            '[ext_resource type="PackedScene" uid="%s" '
            'path="res://assets/landscape/%s.glb" id="%s"]'
            % (UID[name], name, new_id))
        by_name[name] = new_id
        by_id[new_id] = name
        report["added"].append("%s -> id=%s" % (name, new_id))
    if additions:
        txt = txt[:last_ext] + "\r\n" + "\r\n".join(additions) + txt[last_ext:]

    # 3+4. 只改「帶 instance=ExtResource(舊id) 的整行 node 宣告」：
    #      同時換資源與節點名，絕不碰群組根節點（例如「櫻花樹群」）。
    #      ⚠ CJK 沒有 \b 詞界，parent 引用要用路徑片段比對，不能用 \b。
    def parent_refs(node_name):
        """該節點名是否被任何 parent="a/b/名稱/c" 當成路徑片段引用。"""
        return re.search(
            r'parent="(?:[^"]*/)?%s(?:/[^"]*)?"' % re.escape(node_name), txt)

    node_line = re.compile(r'^\[node name="([^"]+)"([^\]]*?)'
                           r'instance=ExtResource\("([^"]+)"\)\]$', re.M)

    counters = {t: 0 for t in targets}
    id_to_target = {by_name[t]: t for t in targets}
    swapped = {t: 0 for t in targets}
    renamed = {t: 0 for t in targets}
    skipped = {t: 0 for t in targets}

    def fix_line(m):
        name, mid, rid = m.group(1), m.group(2), m.group(3)
        t = id_to_target.get(rid)
        if t is None:
            return m.group(0)
        reps = REPLACE[t]
        rep = reps[counters[t] % len(reps)]
        counters[t] += 1
        swapped[t] += 1
        new_name = name
        # 節點被別人當 parent 路徑引用就不改名，只換資源，避免斷鏈
        if name.startswith(t) and not parent_refs(name):
            new_name = rep + name[len(t):]
            renamed[t] += 1
        elif name.startswith(t):
            skipped[t] += 1
        return '[node name="%s"%sinstance=ExtResource("%s")]' % (
            new_name, mid, by_name[rep])

    txt = node_line.sub(fix_line, txt)

    for t in targets:
        report["swaps"][t] = {"count": swapped[t], "to": REPLACE[t]}
        msg = "改名 %d 個" % renamed[t]
        if skipped[t]:
            msg += "（%d 個有 parent 引用，保留原名）" % skipped[t]
        report["renamed"][t] = msg

    # 5. 移除已無人引用的 ext_resource
    for t in targets:
        old_id = by_name[t]
        if re.search(r'ExtResource\("%s"\)' % re.escape(old_id), txt):
            report["removed"].append("%s 仍有引用，保留" % t)
            continue
        txt2 = re.sub(
            r'^\[ext_resource type="PackedScene" uid="[^"]+" '
            r'path="res://assets/landscape/%s\.glb" id="%s"\]\r?\n'
            % (re.escape(t), re.escape(old_id)), "", txt, flags=re.M)
        if txt2 != txt:
            report["removed"].append("%s ext_resource 已移除" % t)
            txt = txt2

    report["changed"] = txt != orig
    if not DRY and report["changed"]:
        io.open(full, "w", encoding="utf-8", newline="").write(txt)
    return report


print("模式：%s" % ("DRY-RUN（不寫檔）" if DRY else "APPLY（寫入磁碟）"))
print("=" * 70)
total = 0
for f in FILES:
    r = process(f)
    if r is None:
        print("%s：無目標樹種" % f)
        continue
    print("\n=== %s" % r["file"])
    for t, info in r["swaps"].items():
        print("   %-10s 替換 %3d 個 -> %s" % (t, info["count"], "/".join(info["to"])))
        total += info["count"]
    for a in r["added"]:
        print("   + 新增資源 %s" % a)
    for t, msg in r["renamed"].items():
        print("   ~ %s %s" % (t, msg))
    for x in r["removed"]:
        print("   - %s" % x)
print("\n" + "=" * 70)
print("合計替換實例：%d" % total)
