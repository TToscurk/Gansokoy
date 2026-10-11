# P11 R2D: P8 limited reseal (frozen hashes of the changed generator files + overlay) and child_seals cascade.
# Run from godot/:  python tools/p11r2d/reseal_p8_branches.py
import json, glob, hashlib, os

def sha_rel(p):  # P8 frozen keys are relative to godot/
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()

def sha_god(p):  # other seals use godot/... keys
    return hashlib.sha256(open('../' + p, 'rb').read()).hexdigest()

def write(f, d):
    raw = open(f, encoding='utf-8').read()
    ind = 1 if raw.startswith('{\n "') else 2
    open(f, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=ind) + '\n')

P8 = 'data/village_v2_p8_seal.json'
d = json.load(open(P8, encoding='utf-8'))
before = hashlib.sha256(open(P8, 'rb').read()).hexdigest()
changed = {}
for k, h in d['frozen'].items():
    n = sha_rel(k)
    if n != h:
        changed[k] = {'old': h, 'new': n}
        d['frozen'][k] = n
if changed:
    d.setdefault('reseal_history', []).append({
        'kind': 'P11_R2D_BRANCHES_FROM_RYUKOTSU', 'date': '2026-10-11', 'changed': changed,
        'seal_file_before': before, 'authorized_by': 'user',
        'authorization': '使用者 2026-10-11 P11 R2D「B — WATERWHEEL IRRIGATION APPROVED WITH CONDITIONS」：水車 2 の竜骨車を N0／原田區／T0 の共同水源とする（竜骨車の追加なし）；必要な P8 limited correction と limited reseal を許可。',
        'reason': '下掛け水車 1／3 は揚水できない（必要揚程 1.57／1.89 m）。高架落とし樋・支柱・接頭・桝・木槽とその碰撞（Feeder_N0／Feeder_T0）を撤去し、竜骨車系統から N0（上段土渠南唇の切欠き＋分水板）・T0（送り樋南壁の分水板）へ盛土の低い土渠＋短い木槽＋道路下の伏越しで送る。輪灌（分水板の開閉で交替）。田・田埂・竜骨車・水車・水渠・地形・道路は不変。'})
    write(P8, d)
    print('P8 frozen reseal', list(changed))

for it in range(10):
    moved = False
    for f in sorted(x.replace(chr(92), '/') for x in glob.glob('data/village_v2_*seal.json')):
        s = json.load(open(f, encoding='utf-8'))
        cs = s.get('child_seals', {})
        upd = {k: [h, sha_god(k)] for k, h in cs.items() if os.path.exists('../' + k) and sha_god(k) != h}
        if upd:
            b = hashlib.sha256(open(f, 'rb').read()).hexdigest()
            for k, (a, n) in upd.items():
                cs[k] = n
            s.setdefault('reseal_history', []).append({
                'kind': 'P11_R2D_CHILD_P8_UPDATE', 'at': '2026-10-11', 'child_seals': upd, 'seal_file_before': b,
                'approved_by': 'user（P11 R2D）', 'reason': 'P11 R2D：子封存 P8（竜骨車支線の limited reseal）の雜湊だけ追従、本封存の内容は不変。'})
            write(f, s)
            print('cascade', it, f, list(upd))
            moved = True
    if not moved:
        break

bad = 0
for f in glob.glob('data/village_v2_*seal.json'):
    s = json.load(open(f, encoding='utf-8'))
    for g in ('frozen', 'child_seals'):
        for k, h in s.get(g, {}).items():
            p = k if os.path.exists(k) else '../' + k
            if os.path.exists(p) and hashlib.sha256(open(p, 'rb').read()).hexdigest() != h:
                print('MISMATCH', f, g, k)
                bad += 1
print('seal mismatch', bad)
