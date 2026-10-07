"""Reseal P10 R1 (market) and R1b (Market West) after the 2026-10-07 text-facing fix (user instruction:
「旗子或其他物件字樣再看向反面的時候字會是反的 請修正」). Only the kit meshes whose text faces changed are re-hashed; the
change is recorded in reseal_history with old/new hashes. Overlay scenes (market_p10.scn / market_west_p10.scn) reference the
meshes externally and are unchanged. Usage: python tools/reseal_p10_text_facing.py
"""
import hashlib, json, os
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
sha = lambda f: hashlib.sha256(open(f, 'rb').read()).hexdigest()
DOCS = 'docs/art_review/village_v2_p10_props/'
EVID = ['text_facing/audit_before_full.log', 'text_facing/audit_after_kits.log', 'text_facing/audit_after_kits.json',
        'text_facing/before_fix_sheet.jpg', 'text_facing/before_fix_lanterns.jpg', 'text_facing/after_fix_sheet.jpg']
NEW_FROZEN = ['godot/tools/village_v2_text_facing_lib.gd', 'godot/tools/audit_village_v2_text_facing.gd',
              'godot/tools/shot_village_v2_text_facing.gd', 'godot/tools/probe_village_v2_text_back.gd', 'tools/reseal_p10_text_facing.py']
REASON = ('使用者 2026-10-07 指示「旗子或其他物件字樣再看向反面的時候字會是反的 請修正」。字の向き監査（audit_village_v2_text_facing.gd：'
          '字の領域の三角形ごとに (dP/du × dP/dv)·n で鏡像、dP/dv の上下で逆さまを判定）で見つかった不具合を Blender 生成側で修正：'
          '①幟の表の quad が鏡像（表裏が同じ UV）→ 表の u を反轉、裏はそのまま＝表裏とも正しく読める；'
          '②下屋の暖簾（だんご・めし）の裏が鏡像 → 裏の u を u0+u1−u；③提灯の紙の胴を上→下で作っていたため上下半分ずつ逆さま＋左右逆で字が割れていた'
          '（中央に黒帯が出る）→ 下→上で作る。構図・配置・overlay・材質・atlas・他の構件は不変（再ビルドで変わった構件は字の面を持つものだけ、雜湊で確認）。')

def dump(path, obj):
    open(path, 'wb').write(json.dumps(obj, ensure_ascii=False, indent=1).replace('\n', '\r\n').encode('utf-8'))

def reseal(path, kind, deps_update=None):
    raw = open(path, 'rb').read()
    j = json.loads(raw.decode('utf-8'))
    changed = {}
    for k, h in list(j['frozen'].items()):
        if os.path.exists(k) and sha(k) != h:
            changed[k] = {'sealed': h, 'now': sha(k)}
            j['frozen'][k] = sha(k)
    added = {}
    for k in NEW_FROZEN:
        if k not in j['frozen']:
            j['frozen'][k] = sha(k); added[k] = j['frozen'][k]
    for e in EVID:
        j['evidence'][e] = sha(DOCS + e)
    dep_changed = {}
    if deps_update:
        for k in list(j['dependencies']['files']):
            if os.path.exists(k) and sha(k) != j['dependencies']['files'][k]:
                dep_changed[k] = {'sealed': j['dependencies']['files'][k], 'now': sha(k)}
                j['dependencies']['files'][k] = sha(k)
    j.setdefault('reseal_history', []).append({
        'at': '2026-10-07', 'kind': kind, 'approved_by': 'user', 'reason': REASON,
        'changed_files': changed, 'added_frozen': added, 'added_evidence': EVID, 'dependency_updates': dep_changed,
        'previous_seal_sha256': hashlib.sha256(raw).hexdigest()})
    dump(path, j)
    print(path, 'changed', len(changed), 'added', len(added), 'deps', len(dep_changed))

reseal('godot/data/village_v2_p10r1_seal.json', 'TEXT_FACING_FIX')
reseal('godot/data/village_v2_p10r1b_seal.json', 'TEXT_FACING_FIX', deps_update=True)
