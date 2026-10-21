"""博麗神社 v2：資源相依閉包稽核。

用法：python deps_audit.py          （從 godot/ 為根）
做三件事：
 1. 從 res://maps/shrine_v2/shrine_v2.tscn 出發，遞迴抓所有 res:// 字串（文字與二進位 .res 都掃），列出實際用到的檔案。
 2. 比對禁用清單：assets/landscape、assets/vista、assets/_lod 的樹、D:/資產glb 路徑字串。
 3. 把閉包內所有檔案的 SHA-256 對 D:/資產glb 內所有檔案的 SHA-256（位元相同＝直接拿來用）。
輸出：_review/shrine_v2/deps_audit.txt ＋ stdout 摘要。
"""
import hashlib
import os
import re
import sys
from collections import Counter, deque

ROOT = "D:/神社/shrine/godot"
START = "maps/shrine_v2/shrine_v2.tscn"
DLIB = "D:/資產glb"
OUT = "D:/神社/shrine/_review/shrine_v2/deps_audit.txt"
PAT = re.compile(rb"res://[^\x00\"'\r\n<>|*?]+")
FOLLOW = {".tscn", ".tres", ".res", ".gd", ".gdshader", ".gdshaderinc", ".scn"}
FORBID_DIR = ["assets/landscape/", "assets/vista/", "assets/_lod/", "assets/models/"]
# 例外：已知不是樹的 _lod／models 資源（石階 kit 的踏石／平台石／袖石垣／收頭石、狛犬）
ALLOW_PREFIX = ["assets/_lod/踏石", "assets/_lod/平台石", "assets/_lod/袖石垣", "assets/_lod/收頭石", "assets/models/komainu_a"]


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


seen = {}
q = deque([START])
missing = set()
while q:
    rel = q.popleft()
    if rel in seen:
        continue
    full = os.path.join(ROOT, rel)
    if not os.path.isfile(full):
        missing.add(rel)
        continue
    seen[rel] = os.path.getsize(full)
    ext = os.path.splitext(rel)[1].lower()
    if ext in FOLLOW:
        data = open(full, "rb").read()
        for m in PAT.finditer(data):
            try:
                p = m.group(0).decode("utf-8")[6:]
            except UnicodeDecodeError:
                continue
            p = p.split("::")[0]
            if p not in seen:
                q.append(p)
    # .import 旁檔不跟（匯入結果在 .godot/，來源就是該檔本身）
files = sorted(seen)
by_dir = Counter("/".join(f.split("/")[:3]) for f in files)
print("閉包檔案數", len(files), "（缺檔 %d）" % len(missing))
for k, v in by_dir.most_common():
    print("  %-48s %d" % (k, v))

bad = []
for f in files:
    if any(f.startswith(d) for d in FORBID_DIR) and not any(f.startswith(a) for a in ALLOW_PREFIX):
        bad.append(f)
print("\n禁用目錄命中（排除已知非樹例外）：%d" % len(bad))
for b in bad:
    print("  ", b)

# D 庫位元比對
dh = {}
for dp, dn, fn in os.walk(DLIB):
    for n in fn:
        p = os.path.join(dp, n)
        try:
            dh.setdefault(sha(p), p)
        except OSError:
            pass
print("\nD:/資產glb 檔案 %d（相異雜湊 %d）" % (sum(len(f) for _, _, f in os.walk(DLIB)), len(dh)))
hits = []
for f in files:
    if os.path.splitext(f)[1].lower() in (".glb", ".gltf", ".png", ".jpg", ".jpeg", ".webp", ".bin", ".fbx", ".exr", ".hdr"):
        h = sha(os.path.join(ROOT, f))
        if h in dh:
            hits.append((f, dh[h]))
print("閉包內與 D 庫位元相同的檔案：%d" % len(hits))
for a, b in hits:
    print("  ", a, "==", b)

# 閉包內的 D 庫路徑字串
dstr = []
for f in files:
    if os.path.splitext(f)[1].lower() in (".tscn", ".tres", ".gd", ".gdshader", ".json"):
        t = open(os.path.join(ROOT, f), "rb").read()
        if "資產glb".encode("utf-8") in t:
            dstr.append(f)
print("內文含「資產glb」字串的檔案：%d" % len(dstr))
for d in dstr:
    print("  ", d)

with open(OUT, "w", encoding="utf-8") as fo:
    fo.write("閉包檔案 %d\n" % len(files))
    for f in files:
        fo.write("%10d  %s\n" % (seen[f], f))
    fo.write("\n缺檔：\n" + "\n".join(sorted(missing)) + "\n")
sys.exit(1 if (bad or hits) else 0)
