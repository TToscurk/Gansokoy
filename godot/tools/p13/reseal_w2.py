# P13 W2 limited reseal：本輪で使用者が授權した変更だけを封存へ反映する（他 session の差分を背書しない）。
#   ALLOW＝本輪の実変更：StreetP10 overlay（MKT_006 の竹籠工房 limited correction）／Kit gate（主街 39 棟の設計表を読む）
# それ以外の frozen 不一致が 1 件でもあれば中止。child_seals は ALLOW から派生した seal ファイルの雜湊だけ追従。
# 実行：cd godot && python tools/p13/reseal_w2.py
import json, glob, hashlib, os, sys

AT = '2026-10-12'
ALLOW = {
    'godot/maps/village_v2/gen/street_p10.scn':
        'P13 W2（使用者 2026-10-12 授權 TASK 2）：MKT_006＝竹籠製作兼販売の工房。055_sk_teoke → 055_st_wara（筵・材料束・編みかけ・腰掛け）'
        '＋碰撞 1.4×1.4×0.9 に差し替え。054 荒物平台（販売）は保持。他の節點・anchors 不変（fix_street_mkt006.gd の自己検査：MKT_006 以外 0）。',
    'godot/tools/verify_village_v2_machiya_kit_gate.gd':
        'P13 W2（使用者 2026-10-12 主街 39 棟 APPROVED）：主街 39 棟は data/village_v2_p13_mainstreet.json の実効紀錄（妻入・型）で検証'
        '（ML.effective_rec／ML.apply）。判定基準・容差・項目は不変。187 棟 --regress 0 失敗。',
}


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def path_of(k):
    return k if os.path.exists(k) else '../' + k


def write(f, d):
    raw = open(f, encoding='utf-8').read()
    ind = 1 if raw.startswith('{\n "') else 2
    open(f, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=ind) + '\n')


files = sorted(x.replace(chr(92), '/') for x in glob.glob('data/village_v2_*seal.json'))
# 1) frozen：ALLOW 以外の不一致があれば中止
stray = []
for f in files:
    s = json.load(open(f, encoding='utf-8'))
    for k, h in s.get('frozen', {}).items():
        p = path_of(k)
        if os.path.exists(p) and sha(p) != h and k not in ALLOW:
            stray.append((f, k))
if stray:
    print('中止：本輪外の frozen 不一致', stray)
    sys.exit(1)
changed_seals = set()
for f in files:
    s = json.load(open(f, encoding='utf-8'))
    upd = {k: [h, sha(path_of(k))] for k, h in s.get('frozen', {}).items() if k in ALLOW and sha(path_of(k)) != h}
    if not upd:
        continue
    b = sha(f)
    for k, (a, n) in upd.items():
        s['frozen'][k] = n
    s.setdefault('reseal_history', []).append({'kind': 'P13_W2_LIMITED', 'at': AT, 'frozen': upd, 'seal_file_before': b,
                                               'approved_by': 'user（P13 WAVE 2）', 'reason': ' ／ '.join(ALLOW[k] for k in upd)})
    write(f, s)
    changed_seals.add('godot/' + f)
    print('frozen', f, list(upd))
# 2) child_seals：変更した seal から派生するものだけ追従（反復）
for it in range(12):
    moved = False
    for f in files:
        s = json.load(open(f, encoding='utf-8'))
        cs = s.get('child_seals', {})
        upd = {k: [h, sha(path_of(k))] for k, h in cs.items() if k in changed_seals and sha(path_of(k)) != h}
        subs = {n: e for n, e in s.get('sub_seals', {}).items() if isinstance(e, dict) and e.get('file') in changed_seals and sha(path_of(e['file'])) != e.get('sha256')}
        if not upd and not subs:
            continue
        b = sha(f)
        for k, (a, n) in upd.items():
            cs[k] = n
        for n, e in subs.items():
            upd[e['file']] = [e['sha256'], sha(path_of(e['file']))]
            e['sha256'] = upd[e['file']][1]
        s.setdefault('reseal_history', []).append({'kind': 'P13_W2_CHILD_UPDATE', 'at': AT, 'child_seals': upd, 'seal_file_before': b,
                                                   'approved_by': 'user（P13 WAVE 2）', 'reason': 'P13 W2：子封存の雜湊だけ追従、本封存の内容は不変。'})
        write(f, s)
        changed_seals.add('godot/' + f)
        print('cascade', it, f, [k.split('/')[-1] for k in upd])
        moved = True
    if not moved:
        break
bad = 0
for f in files:
    s = json.load(open(f, encoding='utf-8'))
    for g in ('frozen', 'child_seals'):
        for k, h in s.get(g, {}).items():
            p = path_of(k)
            if os.path.exists(p) and sha(p) != h:
                print('MISMATCH', f, g, k)
                bad += 1
print('seal mismatch', bad)
