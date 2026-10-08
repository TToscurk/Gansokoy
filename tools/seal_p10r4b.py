"""P10 R4b Human-Use Expansion Batch 1 — A/B FINAL seal writer（使用者裁定 2026-10-08：A 農田・B 住宅＝ART_APPROVED、C 水岸＝ART_REJECTED）。
Writes godot/data/village_v2_p10r4b_seal.json from the scene snapshot (godot/data/village_v2_p10r4b_snapshot.json,
written by verify_village_v2_human_use_exp.gd -- --snapshot=...).
Verify: godot --headless --path godot --script res://tools/verify_village_v2_human_use_exp.gd -- --seal
Usage: python tools/seal_p10r4b.py
"""
import glob
import hashlib
import json
import os

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(R)
G = 'godot/'
REASON = ('Three iterations failed to establish readable waterside activities. Existing R4 Pilot C already provides sufficient '
          'waterside human-use evidence. Additional expansion was removed to preserve natural negative space.')


def sha(f):
    return hashlib.sha256(open(f, 'rb').read()).hexdigest()


def g(pat):
    return sorted(f.replace('\\', '/') for f in glob.glob(pat))


K = G + 'assets/village_v2/humanuse_exp_kit/'
frozen_list = [G + f for f in [
    'tools/village_v2_human_use_exp_lib.gd', 'tools/verify_village_v2_human_use_exp.gd', 'tools/shot_p10_human_use_exp.gd',
    'tools/shot_p10_human_use_exp_views.json', 'tools/survey_village_v2_human_use_exp.gd', 'tools/shot_village_v2_topdown.gd',
    'assets/blender/village_v2/build_humanuse_exp_kit.py',
    'maps/village_v2/gen/human_use_exp_p10.scn', 'data/village_v2_p10r4b_snapshot.json']] \
    + [K + 'src/humanuse_exp_kit.glb', K + 'src/modules_blender.json', K + 'humanuse_exp_kit_manifest.json'] \
    + g(K + 'mesh/*.res') + ['tools/seal_p10r4b.py', 'tools/sheet_p10_r4b.py', 'tools/diff_p10_r4b_final.py']
A = 'docs/art_review/village_v2_p10_props/human_use_exp_b1/'
evidence = [A + 'gate/' + f for f in ['plan_r3.json', 'plan_negatives.log', 'scene.log', 'regression_subset.log',
                                      'plan_final.json', 'plan_final.log', 'scene_final.log', 'ab_final_vs_r3.json']] + [A + 'review/README.md']
render = g(A + 'render/*.png')
review = g(A + 'review/*.jpg')
is_c = lambda f: os.path.basename(f).startswith(('XC', 'zoneC'))
images = [f for f in render + review if not is_c(f)]
rejected_files = [f for f in render + review if is_c(f)]
snap = json.load(open(G + 'data/village_v2_p10r4b_snapshot.json', encoding='utf-8'))
r3 = json.load(open(A + 'gate/plan_r3.json', encoding='utf-8'))
clusters = {}
for it in snap['items']:
    c = clusters.setdefault(it['cluster'], {'zone': it['zone'], 'anchor': it['anchor'], 'items': []})
    c['items'].append(it['id'])
rej_items = [{'cluster': it['cluster'], 'id': it['id'], 'position': it['p'], 'yaw_deg': it['yaw_deg'], 'who': it['who'], 'why': it['why']}
             for it in r3['items'] if it['zone'] == 'C']
rej_cl = [{'id': c['id'], 'anchor': c['anchor'], 'desc': c['anchor_desc'], 'n': c['n']} for c in r3['clusters'] if c['zone'] == 'C']
seal = {
    'schema': 1, 'phase': 'P10 R4b Human-Use Expansion Batch 1 — A/B FINAL（A 農田 5 群・B 住宅 5 群；C 水岸 3 群は ART_REJECTED・除去）',
    'status': 'ART_APPROVED', 'approved_by': 'user', 'approved_date': '2026-10-08',
    'approval_source': '使用者 2026-10-08「P10 R4b Batch 1 — Final Art Decision」：A Farmland＝ART_APPROVED、B Residential＝ART_APPROVED、'
                       'C Waterside＝ART_REJECTED、四個中距離 2/5 的 A/B 次要群組＝ACCEPTED / NON-BLOCKING；「移除 C 後，如果 A/B 完全沒有美術修改，且相關驗證全部通過，可以直接封存」',
    'verdicts': {
        'A': 'ART_APPROVED：農田 5 群（出荷の積み込み・農具置き場と柄の付け替え・稲架の列・橋詰めで降ろした荷・藁塚の陰の一服）',
        'B': 'ART_APPROVED：住宅 5 群（染め物の内職・桶の直し・家庭菜園・荷造り・冬の漬物）',
        'C': 'ART_REJECTED：水岸 3 群（野菜洗い・橋板張り替え・泥上げ）を正式配置から除去',
        'secondary': 'ACCEPTED / NON-BLOCKING：XA2 農具置き場・XA5 一服・XB2 桶直し・XB5 漬物（中距離 2/5）＝secondary ambient detail、15 m で輪郭を要求しない'},
    'value': '10 個已核准生活群組，位置、用途與物件配置都不再修改；不要再為了提高評分而增加物件。',
    'rejected': {
        'status': 'ART_REJECTED', 'clusters': [c['id'] for c in rej_cl], 'reason': REASON,
        'detail': rej_cl, 'items': rej_items, 'n_items': len(rej_items),
        'generator': 'godot/tools/village_v2_human_use_exp_lib.gd::rejected_c()（記録だけ；design()／plan()／bake() は出力しない、gate HUX が検証）',
        'asset': 'humanuse_exp_kit の hx_doroage（XC3 専用に作った缺件）は rejected candidate として kit に残し、配置しない（REJECTED_NEW_IDS）',
        'review_files': 'rejected_candidates（render XC*・review XC*／zoneC）＝r3 審圖の記録',
        'not_replaced': '曬漁網・曬布架など高い輪郭の道具で代替しない（使用者指示）',
        'r4_pilot_c': 'R4 Pilot C（封存 village_v2_p10r4_seal.json の水車の修理・米俵・洗濯）は不変'},
    'mount': 'village_v2 root 直下 Props → HumanUseP10 → HumanUseExpansionP10（HumanUseP10 の次）。Props の子は封存どおり MarketP10 → StreetP10 → MarketWestP10 → EnvironmentP9。',
    'unchanged_proof': {
        'plan': 'C 除去後の計画 40 件＝承認時 r3 の A/B 40 件（id・zone・cluster・anchor・who・why・位置・朝向が完全一致、gate/plan_final.json vs gate/plan_r3.json）',
        'render': 'A/B 31 視點×3 状態を再撮影して r3 と比較（gate/ab_final_vs_r3.json）：BEFORE（擴張なし）の差＝run 間の揺れを基準に、超過は XA4 の 2 視點（背景の XC3 が消えた所）と XB3 near の植え込みの揺れだけ',
        'scene': 'R4 の 50 件 snapshot 位置 ≤ 1 cm・Population 51・Props の子は封存どおり（scene_final.log）'},
    'rule': '封存後は HumanUseExpansionP10 の配置・資產・生成器を変更しない（真正の placement／collision bug のみ HUX_ALLOW_REBAKE=1＋使用者同意＋reseal）。'
            'Batch 2・水岸の追加擴張は使用者の指示があるまで開始しない。共用 prefab tools/village_v2_machiya_kit_prefab.gd は他 Kit と共用のため凍結しない。',
    'roster': {'total': snap['total'], 'zones': snap['zones'], 'clusters': clusters, 'snapshot': G + 'data/village_v2_p10r4b_snapshot.json',
               'assets': {'reused_items': sum(1 for it in snap['items'] if not it['id'].startswith('hx_')),
                          'new_placed': sorted({it['id'] for it in snap['items'] if it['id'].startswith('hx_')}),
                          'new_kit': 'humanuse_exp_kit（hx_hatake・hx_daikon_kake 配置／hx_doroage は rejected candidate）'}},
    'verification': {'plan': 14, 'negatives': 19, 'build_readback': 1, 'scene': 11, 'seal': 13, 'tag': 'HUX'},
    'frozen': {f: sha(f) for f in frozen_list},
    'evidence': {f: sha(f) for f in evidence},
    'art_review_images': {f: sha(f) for f in images},
    'rejected_candidates': {f: sha(f) for f in rejected_files},
    'child_seals': {f: sha(f) for f in [G + 'data/' + n for n in [
        'village_v2_p10r4_seal.json', 'village_v2_p10r3b_seal.json', 'village_v2_p10r3c_seal.json', 'village_v2_p10r3d_seal.json',
        'village_v2_p10r3e_seal.json', 'village_v2_p10_npclib_seal.json', 'village_v2_p10r1_seal.json', 'village_v2_p10r1b_seal.json',
        'village_v2_p10r2_seal.json', 'village_v2_p9_final_seal.json', 'village_v2_p9r53_seal.json', 'village_v2_p9r54_seal.json',
        'village_v2_p8_seal.json']]},
}
open(G + 'data/village_v2_p10r4b_seal.json', 'wb').write((json.dumps(seal, ensure_ascii=False, indent=1) + '\n').encode('utf-8'))
print('sealed frozen', len(seal['frozen']), 'evidence', len(evidence), 'images', len(images), 'rejected', len(rejected_files),
      'children', len(seal['child_seals']), 'roster', snap['total'], snap['zones'])
