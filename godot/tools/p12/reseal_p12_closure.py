# P12 FINAL CLOSURE: limited reseal — frozen hashes of the two verifiers that gained the P12 drift registration
# (P9 R4-4 waterside, P9 R5-4 environment), then cascade child_seals / P9 FINAL sub_seals hash updates only.
# Run from godot/:  python tools/p12/reseal_p12_closure.py
import json, glob, hashlib, os

AT = '2026-10-12'
AUTH = '使用者 2026-10-12「P12 FINAL CLOSURE — AUTHORIZED」TASK 2／3：植被封存差異を精確・可追溯に登記（再生成なし）'
TARGET = {
    'data/village_v2_p9r44_seal.json': ('godot/tools/verify_village_v2_waterside.gd',
        'P11 R2C の河岸 RB_11_-7 局部重烘で WatersideP9 の同 seed 計画が漂移（計画上の wk_reed_s@(329.7,-47.2) が水車入口帯）。'
        '封存実物 Plants/120_wk_reed_s@(328.75,-45.25) は同じ _blocked 判定で通路外、scene 實走 56 點 0 阻擋。蘆葦は再生成しない。'
        'verifier に P12_DRIFT（障害集合・上游 RB_11_-7 lod0/lod1・封存 waterside_p9.scn の雜湊・計画摘要・実物位置）を固定、全一致時のみ容認＋反向 5 種。'),
    'data/village_v2_p9r54_seal.json': ('godot/tools/verify_village_v2_environment.gd',
        'P11 R2D の農田水利（farmland_p8.scn）が MeadowP9 規劃の避障入力を変え、同 seed 再計算 114574 ≠ 封存近級 114105。'
        '封存 meadow_p9.scn（153,772 instance 全 LOD）保持、支線土渠外法内 0・道路面 0。草は再生成しない。'
        'verifier に P12_MEADOW_DRIFT（封存近級・現株数・株位摘要・上游 farmland_p8.scn・封存 meadow_p9.scn の雜湊）を固定、全一致時のみ容認＋反向 4 種。'),
}

def sha(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()

def write(f, d):
    raw = open(f, encoding='utf-8').read()
    ind = 1 if raw.startswith('{\n "') else 2
    open(f, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=ind) + '\n')

for f, (k, reason) in TARGET.items():
    d = json.load(open(f, encoding='utf-8'))
    old = d['frozen'][k]
    new = sha('../' + k)
    if old == new:
        continue
    before = sha(f)
    d['frozen'][k] = new
    d.setdefault('reseal_history', []).append({'kind': 'P12_CLOSURE_SEALED_DRIFT_REGISTRATION', 'at': AT,
        'frozen': {k: [old, new]}, 'seal_file_before': before, 'approved_by': 'user', 'authorization': AUTH, 'reason': reason})
    write(f, d)
    print('frozen reseal', f, k)

for it in range(12):
    moved = False
    for f in sorted(x.replace(chr(92), '/') for x in glob.glob('data/village_v2_*seal.json')):
        s = json.load(open(f, encoding='utf-8'))
        upd = {}
        cs = s.get('child_seals', {})
        for k, h in cs.items():
            if os.path.exists('../' + k) and sha('../' + k) != h:
                upd[k] = [h, sha('../' + k)]
        subs = s.get('sub_seals', {})
        for name, e in subs.items():
            if isinstance(e, dict) and 'sha256' in e and os.path.exists('../' + e['file']) and sha('../' + e['file']) != e['sha256']:
                upd[e['file']] = [e['sha256'], sha('../' + e['file'])]
        if not upd:
            continue
        b = sha(f)
        for k, (a, n) in upd.items():
            if k in cs:
                cs[k] = n
            for e in subs.values():
                if isinstance(e, dict) and e.get('file') == k:
                    e['sha256'] = n
        s.setdefault('reseal_history', []).append({'kind': 'P12_CLOSURE_CHILD_UPDATE', 'at': AT, 'child_seals': upd,
            'seal_file_before': b, 'approved_by': 'user（P12 FINAL CLOSURE）',
            'reason': 'P12 FINAL CLOSURE：子封存（P9 R4-4／R5-4 の差異登記、P10 R4b の HUX 核准位置）の雜湊だけ追従、本封存の内容は不変。'})
        write(f, s)
        print('cascade', it, f, [k.split('/')[-1] for k in upd])
        moved = True
    if not moved:
        break

bad = 0
for f in glob.glob('data/village_v2_*seal.json'):
    s = json.load(open(f, encoding='utf-8'))
    for g in ('frozen', 'child_seals'):
        for k, h in s.get(g, {}).items():
            p = k if os.path.exists(k) else '../' + k
            if os.path.exists(p) and sha(p) != h:
                print('MISMATCH', f, g, k); bad += 1
    for e in s.get('sub_seals', {}).values():
        if isinstance(e, dict) and 'sha256' in e and sha('../' + e['file']) != e['sha256']:
            print('MISMATCH sub', f, e['file']); bad += 1
print('seal mismatch', bad)
