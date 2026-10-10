"""P11 R1 — Collision & Navigation：P9 R4-2／R4-3 の scene gate（實走）limited verifier correction に伴う limited reseal。

  python tools/seal_p11_r1.py   → data/village_v2_p9r42_seal.json・p9r43_seal.json の frozen（verifier 1 件ずつ）だけ更新し reseal_history に記録、
                                  P9 FINAL SEAL（data/village_v2_p9_final_seal.json）の sub_seals の該当 2 件の雜湊を追従・events／reseal_history に記録
  検証：verify_village_v2_shrine_grove.gd --seal／--scene／--scene-negatives、verify_village_v2_school_yard.gd --seal／--scene／--scene-negatives、
        verify_village_v2_p9_final.gd

使用者（2026-10-10 P11 指示）：「P9 R4-2：神社參道 40 個碰撞阻擋點」「P9 R4-3：寺子屋巡邏 NPC 阻擋玩家」「先判定真正原因，再採用最小修正」
  「不得單純降低 Gate 標準、停用碰撞或刪除 NPC 來取得 PASS」「已封存內容只允許有明確原因的 limited correction，必須保留前後 hash、依賴與反向測試」
P10 FINAL CLOSEOUT：「P11 確定參道碰撞後 → P9 R4-2 limited verifier correction／reseal」。
生成器・overlay・地面 shader・ART_REVIEW 圖・status（ART_APPROVED）は不変。冪等：同じ kind があれば old は保持し new だけ更新。
"""
import hashlib
import json
import os

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
EV = 'docs/art_review/village_v2_p11/r1/'
DATE = '2026-10-10'
AUTH = ('使用者 2026-10-10「P11 — Collision & Navigation」：Step 1「P9 R4-2：神社參道 40 個碰撞阻擋點」「P9 R4-3：寺子屋巡邏 NPC 阻擋玩家」'
        '「先判定真正原因，再採用最小修正」「不得單純降低 Gate 標準、停用碰撞或刪除 NPC 來取得 PASS」'
        '「已封存內容只允許有明確原因的 limited correction，必須保留前後 hash、依賴與反向測試」')


def sha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


def load(f):
    raw = open(f, 'rb').read()
    return json.loads(raw.decode('utf-8')), raw


def dump(f, d, indent, crlf, trailing):
    s = json.dumps(d, ensure_ascii=False, indent=indent)
    if crlf:
        s = s.replace('\n', '\r\n')
    if trailing:
        s += '\r\n' if crlf else '\n'
    open(f, 'wb').write(s.encode('utf-8'))


def reseal(seal_path, indent, kind, reason, negatives, evidence):
    d, raw = load(seal_path)
    before = sha(seal_path)
    changed = {}
    for k, v in d['frozen'].items():
        now = sha(k)
        if now != v:
            changed[k] = {'old': v, 'new': now}
    hist = d.setdefault('reseal_history', [])
    ent = next((h for h in hist if h.get('kind') == kind), None)
    if ent is None:
        ent = {'kind': kind, 'date': DATE, 'changed': {}, 'seal_file_before': before}
        hist.append(ent)
    for k, c in changed.items():
        if k in ent['changed']:
            ent['changed'][k]['new'] = c['new']
        else:
            ent['changed'][k] = c
        d['frozen'][k] = c['new']
    ent.update({'authorized_by': 'user', 'authorization': AUTH, 'reason': reason, 'negatives': negatives, 'evidence': evidence,
                'unchanged': '生成器・overlay（gen/*.scn）・地面 shader・ART_REVIEW 總表・證據・status（ART_APPROVED）・掛載順序は不変。'})
    dump(seal_path, d, indent, raw.count(b'\r\n') > 0, raw.endswith(b'\n'))
    print('%s：frozen 変更 %d（%s）seal %s → %s' % (seal_path, len(changed), ', '.join(changed), before[:12], sha(seal_path)[:12]))
    return before


R42 = 'godot/data/village_v2_p9r42_seal.json'
R43 = 'godot/data/village_v2_p9r43_seal.json'
FIN = 'godot/data/village_v2_p9_final_seal.json'

b42 = reseal(R42, 1, 'P11_R1_WALKABLE_SURFACE_VERIFIER_CORRECTION',
             'scene gate「實走：參道＋前庭」の膠囊基準高さを地形 S.h 固定から「歩行面」（下向き射線で最初の地形、または登記歩行面＝root/ShrineApproachP10 の RampCollision だけ）へ。'
             '真因：P10 R6b の參道斜坡碰撞は地形より 0.51–0.94 m 高い歩行面で、旧版はその上を歩く膠囊を「斜坡に埋まる」と 40／179 点で誤判定（歩行面基準では 0）。'
             '未登記の物体は従来どおり障害。追加（厳しくなる方向）：隣接標本 0.5 m の歩行面段差 ≤ 0.45 m。膠囊寸法・ルート・標本間隔は不変。'
             '玩家実走（tools/walk_p10_final.gd --start=trail、參道上り 69 m／下り 90 m）で BLOCKED／STUCK 0。',
             ['--scene-negatives N1 參道の歩行面に箱 → 被擋 3', 'N2 斜坡碰撞を 0.8 m 持ち上げ → 被擋 5・段差 4', 'N3 未登記の台 → 被擋 5', '--seal 竄改反向（従来どおり）'],
             [EV + 'diag/known3.json', EV + 'gates/shrine_scene.log', EV + 'gates/shrine_scene_negatives.log', EV + 'walk_r1/walk_log.json'])
b43 = reseal(R43, 2, 'P11_R1_NPC_DYNAMIC_VERIFIER_CORRECTION',
             'scene gate「實走：入口＋前庭＋南側院＋北側通路」で、P10 R3d が後から加えた巡回 NPC（AnimatableBody3D）を静的被擋の対象から外し、NPC の動的規則を追加：'
             '①待機点（idle 位置・巡回両端）とルートの距離 ≥ 0.3＋NPC 半径＋0.3、②巡回がルート帯の中を歩く長さ ≤ 1.5 m、③横切り点の静的通行幅 ≥ 2×(0.3＋NPC 半径)＋0.3。'
             '真因：C20 の巡回（202.0,20.4）↔（206.4,25.6）が入口ルートを 1 箇所で横切り、読み込み直後の巡回位置（start_u 0.69）がちょうど横切り点にあった。'
             'NPC を除くと静的被擋 0、巡回両端はルートから 1.35 m、横切り点の静的通行幅 6.70 m。静的障害の判定は旧版どおり。NPC・巡回は変更なし。'
             '玩家実走：入口ルート 3 往復で NPC_CONTACT 0・BLOCKED 0。',
             ['--scene-negatives N1 静的な箱 → 被擋 3', 'N2 C20 を idle にして横切り点 → 待機点', 'N3 巡回の片端をルート上 → 待機点', 'N4 巡回をルートに沿わせる 4 m → 沿い＋待機点', '--seal 竄改反向（従来どおり）'],
             [EV + 'diag/known3.json', EV + 'diag/npc.json', EV + 'gates/school_scene.log', EV + 'gates/school_scene_negatives.log', EV + 'walk_r1/walk_log.json'])

fd, fraw = load(FIN)
fin_before = sha(FIN)
upd = {}
for key, path in [('R4_2_shrine_grove', R42), ('R4_3_school_yard', R43)]:
    e = fd['sub_seals'][key]
    now = sha(path)
    if e['sha256'] != now:
        upd[key] = [e['sha256'], now]
        e['sha256'] = now
hist = fd.setdefault('reseal_history', [])
ent = next((h for h in hist if h.get('kind') == 'P11_R1_CHILD_R4_2_R4_3_UPDATE'), None)
if ent is None:
    ent = {'kind': 'P11_R1_CHILD_R4_2_R4_3_UPDATE', 'date': DATE, 'sub_seals': {}, 'seal_file_before': fin_before}
    hist.append(ent)
for k, (o, n) in upd.items():
    if k in ent['sub_seals']:
        ent['sub_seals'][k][1] = n
    else:
        ent['sub_seals'][k] = [o, n]
ent.update({'authorized_by': 'user', 'authorization': AUTH,
            'reason': 'P9 R4-2／R4-3 の scene gate（實走）limited verifier correction（P11 R1）に伴い、子封存の雜湊だけ追従。R1–R5 の封存内容（生成器・overlay・地被）は不変。'})
ev_line = 'P11 R1 LIMITED_VERIFIER_CORRECTION（R4-2 參道歩行面／R4-3 NPC 動的規則；使用者 2026-10-10 P11 指示；village_v2_p9r42_seal.json・p9r43_seal.json reseal_history）'
if ev_line not in fd.get('events', []):
    fd.setdefault('events', []).append(ev_line)
dump(FIN, fd, 1, fraw.count(b'\r\n') > 0, fraw.endswith(b'\n'))
print('%s：sub_seals 更新 %s；seal %s → %s' % (FIN, ', '.join(upd), fin_before[:12], sha(FIN)[:12]))
