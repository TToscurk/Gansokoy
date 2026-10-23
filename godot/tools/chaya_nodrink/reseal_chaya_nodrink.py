# 茶屋少女（chaya_f01）の Drink 削除（使用者 2026-10-16 指示）：R3c／R3d／R3e limited reseal＋child_seals 連動。
# Run from godot/:  python tools/chaya_nodrink/reseal_chaya_nodrink.py
import json, glob, hashlib, os

AT = '2026-10-16'
APPROVED = 'user（2026-10-16 指示「請把茶屋少女 喝水這個動作刪除」）'
DRINK_PATHS = {
    'godot/data/village_v2_p10r3c_seal.json': 'MarketWest/W3_chaya_f01',
    'godot/data/village_v2_p10r3d_seal.json': 'Izakaya/C17_chaya_f01',
    'godot/data/village_v2_p10r3e_seal.json': 'Canal/O8_chaya_f01',
}
REASON = {
    'godot/scripts/npc_activity_overlay.gd': 'R3c ASSIGN から W3 茶屋少女の Drink を削除（W3 は基線 Idle に戻る）。杯の握持・tea_cup・時々飲む処理は未使用の vocabulary として残す。',
    'godot/tools/verify_p10_activity.gd': 'limited verifier correction：指派数 8→7・類型 5→4（Drink 削除に追従）。判定ロジックは不変。',
    'godot/tools/village_v2_population_core_lib.gd': 'R3d ASSIGN から C17 茶屋少女の Drink を削除（基線 Idle）。配役・位置・朝向は不変。',
    'godot/data/village_v2_p10r3d_snapshot.json': 'snapshot の C17 から activity（Drink）を削除。位置・朝向・mode は不変。',
    'godot/tools/village_v2_population_outer_lib.gd': 'R3e ASSIGN から O8 茶屋少女の Drink を削除（基線 Idle）。配役・位置・朝向は不変。',
    'godot/data/village_v2_p10r3e_snapshot.json': 'snapshot の O8 から activity（Drink）を削除。位置・朝向・mode は不変。',
}


def sha(p):
    return hashlib.sha256(open('../' + p, 'rb').read()).hexdigest()


def fsha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


files = sorted(f.replace(chr(92), '/') for f in glob.glob('data/village_v2_*seal.json'))
seals = {f: json.load(open(f, encoding='utf-8')) for f in files}
changed = set()


def write(f):
    raw = open(f, encoding='utf-8').read()
    ind = 1 if raw.startswith('{\n "') else 2
    open(f, 'w', encoding='utf-8', newline='\n').write(json.dumps(seals[f], ensure_ascii=False, indent=ind) + '\n')


for f, d in seals.items():
    key = 'godot/' + f
    fr = d.get('frozen', {})
    upd = {k: [h, sha(k)] for k, h in fr.items() if k in REASON and sha(k) != h}
    content = {}
    if key in DRINK_PATHS:
        path = DRINK_PATHS[key]
        if key.endswith('r3c_seal.json') and path in d.get('assignments', {}):
            rec = d['assignments'].pop(path)
            d.setdefault('removed_assignments', {})[path] = dict(rec, removed=AT, approved_by=APPROVED)
            content['assignments'] = 'removed ' + path + ' → removed_assignments'
        for listname in ('added', 'outer'):
            for a in d.get(listname, []):
                if '%s_%s' % (a['id'], a['model']) == path.split('/')[1] and 'activity' in a:
                    a.pop('activity')
                    content[listname] = a['id'] + ' activity removed'
    if upd or content:
        before = fsha(f)
        for k, (a, b) in upd.items():
            fr[k] = b
        d.setdefault('reseal_history', []).append({
            'kind': 'CHAYA_DRINK_REMOVED', 'at': AT, 'frozen': upd, 'content': content,
            'seal_file_before': before, 'approved_by': APPROVED,
            'reason': '茶屋少女（chaya_f01）の喝水（Drink：drinking_im1_a030＋茶碗）を全配置から削除し、基線 Idle に戻す。人數・位置・朝向・mode は不変。 '
                      + ' '.join(REASON[k] for k in upd)})
        write(f)
        changed.add(key)
        print('reseal', f, list(upd), content)

# 連動は本スクリプトで書き換えた封存を指す child_seals だけ（既存の無関係な不一致は触らない）
for it in range(10):
    moved = False
    for f, d in seals.items():
        cs = d.get('child_seals', {})
        upd = {k: [h, sha(k)] for k, h in cs.items()
               if k in changed and sha(k) != h}
        if upd:
            before = fsha(f)
            for k, (a, b) in upd.items():
                cs[k] = b
            d.setdefault('reseal_history', []).append({
                'kind': 'CHAYA_DRINK_REMOVED_CHILD_CASCADE', 'at': AT, 'child_seals': upd,
                'seal_file_before': before, 'approved_by': APPROVED,
                'reason': '茶屋少女 Drink 削除：子封存（R3c／R3d／R3e）の雜湊だけ追従、本封存の内容は不変。'})
            write(f)
            changed.add('godot/' + f)
            print('cascade', it, f, list(upd))
            moved = True
    if not moved:
        break
