# P13 W3B 驗收後：Before／After 證據の来歴を、既存のバックアップ・画像・ハッシュだけで確かめる（唯讀。Godot は起動しない・再撮影しない）。
#   uv run --no-project --with pillow --with numpy python tools/p13/check_before_provenance_w3b.py
# 確かめること：
#   1. 改前バックアップ scn ＝ 元の封存値（e50c84c の P8 seal／LFS 指標）か
#   2. shots/before の TPS／高視角が、改前基線（scratch/orig2）と同じ画像か（orig2 は撮影順が重烘より前の基線）
#   3. glare 基線 glare_orig が旧水材質か（同じ指令で撮った glare_exp＝新生成器・glare_formal＝重烘後 と水面輝度を比べる）
#   4. 参考：各ディレクトリの撮影時間線（重烘の時刻は最後の 1 回しか残っていない）
import datetime
import glob
import hashlib
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
W = os.path.join(os.environ["LOCALAPPDATA"], "hermes", "cache", "scratch", "w3b")
WAVE = os.path.join(REPO, "docs", "art_review", "village_v2_p13", "wave3b")
B = os.path.join(WAVE, "shots")
BACKUP = os.path.join(REPO, "godot", ".godot", "w3b_backup", "farmland_p8_before.scn")
SCENE = os.path.join(REPO, "godot", "maps", "village_v2", "gen", "farmland_p8.scn")
BUILD_LOG = os.path.join(WAVE, "evidence", "p8_build.log")
SCN_GIT = "godot/maps/village_v2/gen/farmland_p8.scn"
VIEWS = ["N0_tps", "T0_down_tps", "T0_up_tps", "high_farm"]


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for ch in iter(lambda: f.read(1 << 20), b""):
            h.update(ch)
    return h.hexdigest()


def git(*a):
    return subprocess.run(["git", "-C", REPO, "-c", "core.quotepath=false"] + list(a), capture_output=True).stdout


def pointer_oid(rev):
    out = git("cat-file", "-p", "%s:%s" % (rev, SCN_GIT)).decode("utf-8", "replace")
    for ln in out.splitlines():
        if ln.startswith("oid sha256:"):
            return ln.split(":", 1)[1].strip()
    return "(LFS 指標ではない)"


def ts(t):
    return datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M:%S")


def img(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32)


def lum(a):
    return (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]) / 255.0


def magenta(p):
    mg = img(p)
    return (mg[..., 0] > 170) & (mg[..., 2] > 170) & (mg[..., 1] < 100)


def pdiff(a, b):
    d = np.abs(img(a) - img(b)).sum(axis=2)
    return float(d.mean()), float((d > 30).mean() * 100.0)


print("== 1. 改前バックアップ scn の来歴（ハッシュ）")
seal_old = json.loads(git("show", "e50c84c:godot/data/village_v2_p8_seal.json"))["frozen"]["maps/village_v2/gen/farmland_p8.scn"]
b = sha(BACKUP)
print("[PROV] backup 実測          ", b)
print("[PROV] e50c84c の P8 封存値 ", seal_old)
print("[PROV] e50c84c の LFS 指標  ", pointer_oid("e50c84c"))
print("[PROV] → バックアップ＝元の封存版：", b == seal_old == pointer_oid("e50c84c"))
cur = sha(SCENE)
print("[PROV] 現行 scn 実測        ", cur)
print("[PROV] HEAD の LFS 指標     ", pointer_oid("HEAD"))
print("[PROV] → 現行＝HEAD の指標：", cur == pointer_oid("HEAD"))

print("\n== 2. 撮影の時間線（重烘の時刻は最後の 1 回だけ残る）")
rows = []
for d in ["orig", "sample", "orig2", "exp1", "exp2", "exp3", "exp4", "exp5", "glare_orig", "glare_exp", "glare_formal", "scan", "repro", "ends_old", "ends"]:
    fs = glob.glob(os.path.join(W, d, "*.png"))
    if fs:
        t = [os.path.getmtime(f) for f in fs]
        rows.append((min(t), "%s → %s | scratch/%s（%d 枚）" % (ts(min(t)), ts(max(t))[11:], d, len(fs))))
for lab, p in [("[改前バックアップ scn を作った時刻]", BACKUP), ("[最後の P8 重烘 scn の更新]", SCENE), ("[p8_build.log＝最後の build の終了]", BUILD_LOG)]:
    rows.append((os.path.getmtime(p), "%s | %s" % (ts(os.path.getmtime(p)), lab)))
for sub in ["before", "after"]:
    fs = [f for f in glob.glob(os.path.join(B, sub, "*.png")) if "__m_" not in f]
    t = [os.path.getmtime(f) for f in fs]
    rows.append((min(t), "%s → %s | docs/…/shots/%s（%d 枚）" % (ts(min(t)), ts(max(t))[11:], sub, len(fs))))
for _, line in sorted(rows):
    print("[PROV]", line)

print("\n== 3. shots/before の画像内容（同じ 4 視点）")
print("[PROV] 比較          平均絶対差/765   差>30 の画素率")
for v in VIEWS:
    bp = os.path.join(B, "before", v + ".png")
    ap = os.path.join(B, "after", v + ".png")
    o2 = os.path.join(W, "orig2", v + ".png")
    out = ["%-12s" % v]
    if os.path.exists(o2):
        m, p = pdiff(bp, o2)
        out.append("before↔orig2(改前基線) %.2f / %.2f%%" % (m, p))
    else:
        out.append("before↔orig2: (orig2 に無し)")
    m, p = pdiff(bp, ap)
    out.append("before↔after %.2f / %.2f%%" % (m, p))
    print("[PROV]", " | ".join(out))

print("\n== 3b. 土メッシュのマスク面積（盛土が入ると面積が増える。旧幾何なら小さい）")
for v in VIEWS:
    cnt = {}
    for lab, p in [("before", os.path.join(W, "masks_final", "before", v + "__m_earth.png")), ("orig2", os.path.join(W, "orig2", v + "__m_earth.png")), ("after", os.path.join(W, "masks_final", "after", v + "__m_earth.png"))]:
        cnt[lab] = int(magenta(p).sum()) if os.path.exists(p) else None
    ratio = (cnt["after"] / cnt["before"]) if cnt.get("before") and cnt.get("after") else float("nan")
    print("[PROV] %-12s before %s | orig2 %s | after %s | after/before ×%.2f" % (v, cnt["before"], cnt["orig2"], cnt["after"], ratio))

print("\n== 4. glare 基線（glare_orig が旧水材質か）：水面マスク内の平均輝度")
names = sorted(os.path.basename(f)[:-4] for f in glob.glob(os.path.join(W, "glare_orig", "*.png")) if "__m_" not in f)
sel = names[::4]
res = {}
for d in ["glare_orig", "glare_exp", "glare_formal"]:
    tot = 0.0
    npx = 0
    ok = 0
    for n in sel:
        bp = os.path.join(W, d, n + ".png")
        mp = os.path.join(W, d, n + "__m_water.png")
        if not (os.path.exists(bp) and os.path.exists(mp)):
            continue
        m = magenta(mp)
        if m.sum() < 200:
            continue
        L = lum(img(bp))
        tot += float(L[m].sum())
        npx += int(m.sum())
        ok += 1
    res[d] = (tot / npx if npx else float("nan"), ok)
    print("[PROV] %-13s 水面の平均輝度 %.3f（%d view・水面画素 %d）" % (d, res[d][0], ok, npx))
print("[PROV] → exp（新生成器をメモリ内で実行）≈ formal（重烘後）で、orig だけ明るければ glare_orig は旧水材質：orig−formal %.3f / exp−formal %.3f" % (res["glare_orig"][0] - res["glare_formal"][0], res["glare_exp"][0] - res["glare_formal"][0]))

print("\n== 5. 登録用：主要画像の sha256（先頭 16 桁）")
for sub in ["before", "after"]:
    for v in VIEWS:
        p = os.path.join(B, sub, v + ".png")
        print("[PROV] %s/%s.png  %s" % (sub, v, sha(p)[:16]))
