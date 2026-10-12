"""P13 W4：一時 index で commit を作る（使用者の staged 53 項を動かさない）。
  python tools/p13/commit_w4.py                       # dry run（対象一覧と HEAD との差）
  python tools/p13/commit_w4.py --commit              # 実行（既定のメッセージ）
  python tools/p13/commit_w4.py --commit --msg FILE   # 実行（メッセージをファイルから）
手順：HEAD を一時 index に読み込み → 対象を hash-object -w（.gitattributes のフィルタ適用）→ update-index → write-tree → commit-tree → update-ref。
その後、実 index には対象パスの blob だけを同じ値で入れる（HEAD と一致させる＝status に「削除」が出ない）。他のパスの index は触らない。
"""
import os
import subprocess
import sys
import tempfile

REPO = r"D:/神社/shrine"
MSG = """feat(人間之里V2): P13 W4 神社參道 代表区間の石段試作（overlay SandoPilotW4P13・s=37.2–64.2 m・可逆）＋r8 規則性の診断＋洋紅帯の原因調査＋報告

- 診断: r8 は蹴上 変動係数 3.8 %（98 % が平均の ±10 %）＝節拍器。側面は浮空なし・穿插は右端 8 %・露出 >0.6 m が 51/185 段・石と地面の境が硬い線
- 試作: 不規則な踏面（蹴上 CV 18 %・踏面長 CV 19 %、全段が斜坡碰撞の許容帯内）／笠石＋石垣／土の裾（地形と同じシェーダー）。碰撞・Auto-Step・相機は不変
- 洋紅帯: 原因は Districts/LandmarkParcelLines（区画デバッグ線）。ReviewStart だけが隠す。未対処（提案のみ）
- 検証: verify_w4_pilot 0 失敗、SAN plan／scene・SWALK 0 失敗、歩行軌跡が r8／w4 でビット一致
- ART_REVIEW（未 ART_APPROVED）。village_v2.tscn は 3 行のみ。r8 の正式生成器・P8・封存は不変
"""


def git(*args, env=None, inp=None):
    r = subprocess.run(["git", "-C", REPO] + list(args), capture_output=True, env=env, input=inp)
    if r.returncode != 0:
        raise SystemExit("git %s 失敗: %s" % (" ".join(args), r.stderr.decode("utf-8", "replace")))
    return r.stdout.decode("utf-8", "replace").strip()


def targets():
    out = [
        "godot/tools/village_v2_sando_w4_lib.gd",
        "godot/maps/village_v2/scripts_p13/sando_pilot_w4.gd",
        "godot/maps/village_v2/gen/sando_pilot_w4_p13.scn",
        "godot/maps/village_v2/village_v2.tscn",
        "godot/tools/gen_village_v2.gd",                    # W4B：LandmarkParcelLines を visible=false で出力（1 行）
        "docs/art_review/village_v2_p13/wave5_backlog.md",
    ]
    for f in sorted(os.listdir(os.path.join(REPO, "godot/tools/p13"))):
        if "w4" in f and not f.endswith(".uid"):
            out.append("godot/tools/p13/" + f)
    for sub in ("wave4", "wave4b"):
        root = os.path.join(REPO, "docs/art_review/village_v2_p13/" + sub)
        for d, _, fs in os.walk(root):
            for f in sorted(fs):
                out.append(os.path.relpath(os.path.join(d, f), REPO).replace("\\", "/"))
    return out


def head_blob(path):
    r = subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", "-q", "HEAD:" + path], capture_output=True)
    return r.stdout.decode().strip() if r.returncode == 0 else None


def main():
    msg = MSG
    if "--msg" in sys.argv:
        msg = open(sys.argv[sys.argv.index("--msg") + 1], encoding="utf-8").read()
    ts = targets()
    for t in ts:
        assert os.path.exists(os.path.join(REPO, t)), t
    env0 = dict(os.environ)
    env0.pop("GIT_INDEX_FILE", None)
    new, changed, same = [], [], 0
    for t in ts:
        hb = head_blob(t)
        wb = git("hash-object", "--path=" + t, os.path.join(REPO, t), env=env0)
        if hb is None:
            new.append(t)
        elif hb != wb:
            changed.append(t)
        else:
            same += 1
    print("対象 %d 件：HEAD と同一 %d／変更 %d／新規 %d" % (len(ts), same, len(changed), len(new)))
    for t in changed:
        print("  変更", t)
    for t in new:
        print("  新規", t)
    if "--commit" not in sys.argv:
        return
    env = dict(os.environ)
    env.pop("GIT_INDEX_FILE", None)
    head = git("rev-parse", "HEAD", env=env)
    tmp = os.path.join(tempfile.gettempdir(), "w4_commit_index")
    if os.path.exists(tmp):
        os.remove(tmp)
    env2 = dict(env)
    env2["GIT_INDEX_FILE"] = tmp
    git("read-tree", "HEAD", env=env2)
    blobs = {}
    for t in ts:
        b = git("hash-object", "-w", "--path=" + t, os.path.join(REPO, t), env=env)
        blobs[t] = b
        git("update-index", "--add", "--cacheinfo", "100644,%s,%s" % (b, t), env=env2)
    tree = git("write-tree", env=env2)
    commit = git("commit-tree", tree, "-p", head, "-m", msg, env=env)
    git("update-ref", "-m", "P13 W4 pilot", "HEAD", commit, head, env=env)
    os.remove(tmp)
    # 実 index：対象パスだけ HEAD と同じ blob にする
    for t, b in blobs.items():
        git("update-index", "--add", "--cacheinfo", "100644,%s,%s" % (b, t), env=env)
    print("commit", commit)
    print("parent", head)


main()
